defmodule FixlyWeb.Admin.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket
  alias Fixly.Accounts
  alias Fixly.Organizations
  alias Fixly.Assets
  alias Fixly.AI
  alias Fixly.PubSubBroadcast

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    # Subscribe to real-time updates for this org
    if connected?(socket) && org_id do
      PubSubBroadcast.subscribe_org(org_id)
    end

    internal_users = if org_id, do: Accounts.list_users_by_organization(org_id), else: []
    contractor_orgs = if org_id, do: Organizations.list_contractor_orgs(org_id), else: []

    # Build the assignee list (all users + contractor orgs for the filter)
    all_assignees =
      Enum.map(internal_users, fn u -> %{id: u.id, name: u.name || u.email, type: "user"} end) ++
      Enum.map(contractor_orgs, fn o -> %{id: o.id, name: o.name, type: "org"} end)

    # Static reference data for filter dropdowns
    all_categories = Ticket.categories()
    all_locations =
      if org_id do
        Fixly.Locations.get_tree(org_id)
        |> flatten_location_tree()
      else
        []
      end

    socket =
      socket
      |> assign(:page_title, "Tickets")
      |> assign(:view_mode, "list")
      |> assign(:search_query, "")
      # Filters (multi-select comboboxes)
      |> assign(:filter_statuses, MapSet.new())
      |> assign(:filter_priorities, MapSet.new())
      |> assign(:filter_categories, MapSet.new())
      |> assign(:filter_location_ids, MapSet.new())
      |> assign(:filter_date_from, nil)
      |> assign(:filter_date_to, nil)
      |> assign(:show_date_picker, false)
      |> assign(:calendar_month, Date.utc_today())
      |> assign(:filter_assignee_ids, MapSet.new())
      |> assign(:show_filters, false)
      |> assign(:assignee_search, "")
      # Combobox UI state
      |> assign(:show_status_filter, false)
      |> assign(:status_filter_search, "")
      |> assign(:show_priority_filter, false)
      |> assign(:priority_filter_search, "")
      |> assign(:show_category_filter, false)
      |> assign(:category_filter_search, "")
      |> assign(:show_location_filter, false)
      |> assign(:location_filter_search, "")
      # Reference data
      |> assign(:all_assignees, all_assignees)
      |> assign(:all_categories, all_categories)
      |> assign(:all_locations, all_locations)
      # Pagination state
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      # Kanban data (assign-based, not streamed)
      |> assign(:grouped, [])
      |> assign(:kanban_loading, MapSet.new())
      # Panel
      |> assign(:selected_ticket, nil)
      |> assign(:comments, [])
      |> assign(:comment_body, "")
      |> assign(:ai_suggestions, [])
      |> assign(:ai_loading, false)
      |> assign(:location_assets, [])
      |> assign(:org_id, org_id)
      |> assign(:internal_users, internal_users)
      |> assign(:contractor_orgs, contractor_orgs)
      |> assign(:current_user, user)
      |> reload_data()

    {:ok, socket}
  end

  defp flatten_location_tree(nodes, acc \\ []) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc ++ [node] ++ flatten_location_tree(node.children)
    end)
  end

  # --- PubSub Handlers (real-time updates from other users/workers) ---

  @impl true
  def handle_info({:ticket_created, ticket}, socket) do
    # Preload if needed, then insert into stream if it matches current filters
    ticket = Tickets.get_ticket!(ticket.id)

    socket =
      if matches_filters?(ticket, socket.assigns) do
        counts = reload_counts(socket)
        socket
        |> assign(:counts, counts)
        |> stream_insert(:tickets, ticket, at: 0)
        |> maybe_reload_kanban()
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:ticket_updated, ticket}, socket) do
    ticket = Tickets.get_ticket!(ticket.id)

    # Update stream + kanban
    counts = reload_counts(socket)
    socket =
      socket
      |> assign(:counts, counts)
      |> stream_insert(:tickets, ticket)
      |> maybe_reload_kanban()

    # If the updated ticket is the one we have open in the panel, refresh it
    socket =
      if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == ticket.id do
        comments = Tickets.list_comments(ticket.id)
        assign(socket, selected_ticket: ticket, comments: comments)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:sla_breached, ticket}, socket) do
    ticket = Tickets.get_ticket!(ticket.id)
    counts = reload_counts(socket)
    {:noreply, socket |> assign(:counts, counts) |> stream_insert(:tickets, ticket) |> maybe_reload_kanban()}
  end

  def handle_info({:comment_added, _comment}, socket) do
    # Refresh comments if panel is open
    socket =
      if socket.assigns.selected_ticket do
        comments = Tickets.list_comments(socket.assigns.selected_ticket.id)
        assign(socket, :comments, comments)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:refresh_ai_suggestions, socket) do
    socket =
      if socket.assigns.selected_ticket do
        suggestions = AI.list_suggestions_for_ticket(socket.assigns.selected_ticket.id)
        assign(socket, ai_suggestions: suggestions, ai_loading: false)
      else
        assign(socket, ai_loading: false)
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex gap-6 h-full">
      <!-- Main content (shrinks when panel is open) -->
      <div class={["flex-1 min-w-0 space-y-6 transition-all duration-300", @selected_ticket && "lg:mr-0"]}>
        <!-- Stats cards -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card label="Total Tickets" value={@counts.total} icon="hero-ticket" color="primary" />
          <.stat_card label="Open" value={@counts.open} icon="hero-inbox" color="success" />
          <.stat_card label="In Progress" value={@counts.in_progress} icon="hero-arrow-path" color="info" />
          <.stat_card label="On Hold" value={@counts.on_hold} icon="hero-pause-circle" color="warning" />
        </div>

        <!-- Toolbar -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <!-- Top row: view toggle + search -->
          <div class="flex items-center justify-between px-5 py-3 border-b border-base-300">
            <div class="flex items-center gap-2">
              <div class="join">
                <button phx-click="set_view_mode" phx-value-mode="list" class={["join-item btn btn-sm", @view_mode == "list" && "btn-active"]}>
                  <.icon name="hero-bars-3" class="size-4" /> List
                </button>
                <button phx-click="set_view_mode" phx-value-mode="kanban" class={["join-item btn btn-sm", @view_mode == "kanban" && "btn-active"]}>
                  <.icon name="hero-view-columns" class="size-4" /> Kanban
                </button>
              </div>
              <div class="divider divider-horizontal mx-0 h-6"></div>
              <button phx-click="toggle_filters" class={["btn btn-sm gap-1.5", @show_filters && "btn-primary btn-outline", !@show_filters && "btn-ghost"]}>
                <.icon name="hero-adjustments-horizontal" class="size-4" />
                Filters
                <span :if={active_filter_count(assigns) > 0} class="badge badge-xs badge-primary">{active_filter_count(assigns)}</span>
              </button>
              <button :if={active_filter_count(assigns) > 0} phx-click="clear_all_filters" class="btn btn-sm btn-ghost text-error gap-1">
                <.icon name="hero-x-mark" class="size-3.5" /> Clear all
              </button>
            </div>
            <form phx-change="search" phx-submit="search" class="relative hidden sm:block">
              <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search tickets..."
                class="input input-sm input-bordered pl-9 w-56"
                phx-debounce="300"
                autocomplete="off"
              />
              <button :if={@search_query != ""} type="button" phx-click="clear_search" class="absolute right-2 top-1/2 -translate-y-1/2 text-base-content/40 hover:text-base-content">
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            </form>
          </div>

          <!-- Active filter chips -->
          <div :if={active_filter_count(assigns) > 0} class="flex flex-wrap items-center gap-1.5 px-5 py-2 border-b border-base-200 bg-base-200/30">
            <span class="text-xs text-base-content/50 mr-1">Active:</span>
            <.filter_chip :if={MapSet.size(@filter_statuses) > 0} label={"Status (#{MapSet.size(@filter_statuses)})"} event="clear_status_filter" value="" />
            <.filter_chip :if={MapSet.size(@filter_priorities) > 0} label={"Priority (#{MapSet.size(@filter_priorities)})"} event="clear_priority_filter" value="" />
            <.filter_chip :if={MapSet.size(@filter_categories) > 0} label={"Category (#{MapSet.size(@filter_categories)})"} event="clear_category_filter" value="" />
            <.filter_chip :if={@filter_date_from || @filter_date_to} label={date_range_label(@filter_date_from, @filter_date_to)} event="clear_filter" value="date_range" />
            <.filter_chip :if={MapSet.size(@filter_location_ids) > 0} label={"Location (#{MapSet.size(@filter_location_ids)})"} event="clear_location_filter" value="" />
            <.filter_chip
              :for={aid <- MapSet.to_list(@filter_assignee_ids)}
              label={assignee_name(aid, @all_assignees)}
              event="remove_assignee"
              value={aid}
            />
          </div>

          <!-- Filter panel (collapsible) -->
          <div :if={@show_filters} class="px-5 py-4 border-b border-base-300 bg-base-200/20">
            <!-- Row 1: Status, Priority, Category, Location comboboxes -->
            <div class="flex items-center gap-2 mb-3">
              <!-- Status combobox -->
              <div class="relative" phx-click-away="close_status_filter">
                <button phx-click="toggle_status_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                  <div class="flex items-center gap-1.5 flex-1 min-w-0">
                    <span :if={MapSet.size(@filter_statuses) == 0} class="text-base-content/60">All Statuses</span>
                    <span :if={MapSet.size(@filter_statuses) > 0} class="flex items-center gap-1">
                      <span class="badge badge-xs badge-primary">{MapSet.size(@filter_statuses)}</span>
                      <span class="text-xs truncate">selected</span>
                    </span>
                  </div>
                  <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                </button>
                <div :if={@show_status_filter} class="absolute z-30 mt-1 w-64 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                  <div class="p-2 border-b border-base-200">
                    <form phx-change="search_status_filter">
                      <input type="text" name="query" value={@status_filter_search} placeholder="Search statuses..." class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                    </form>
                  </div>
                  <div class="max-h-56 overflow-y-auto p-1">
                    <button
                      :for={{val, label} <- filtered_ticket_statuses(@status_filter_search)}
                      phx-click="toggle_status_item"
                      phx-value-id={val}
                      class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_statuses, val) && "bg-primary border-primary", !MapSet.member?(@filter_statuses, val) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_statuses, val)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class={["w-2.5 h-2.5 rounded-full shrink-0", status_dot_color(val)]}></span>
                      <span class="text-sm">{label}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_status_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_status_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <!-- Priority combobox -->
              <div class="relative" phx-click-away="close_priority_filter">
                <button phx-click="toggle_priority_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                  <div class="flex items-center gap-1.5 flex-1 min-w-0">
                    <span :if={MapSet.size(@filter_priorities) == 0} class="text-base-content/60">All Priorities</span>
                    <span :if={MapSet.size(@filter_priorities) > 0} class="flex items-center gap-1">
                      <span class="badge badge-xs badge-primary">{MapSet.size(@filter_priorities)}</span>
                      <span class="text-xs truncate">selected</span>
                    </span>
                  </div>
                  <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                </button>
                <div :if={@show_priority_filter} class="absolute z-30 mt-1 w-64 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                  <div class="p-2 border-b border-base-200">
                    <form phx-change="search_priority_filter">
                      <input type="text" name="query" value={@priority_filter_search} placeholder="Search priorities..." class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                    </form>
                  </div>
                  <div class="max-h-56 overflow-y-auto p-1">
                    <button
                      :for={{val, label} <- filtered_ticket_priorities(@priority_filter_search)}
                      phx-click="toggle_priority_item"
                      phx-value-id={val}
                      class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_priorities, val) && "bg-primary border-primary", !MapSet.member?(@filter_priorities, val) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_priorities, val)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class={["w-2.5 h-2.5 rounded-full shrink-0", priority_dot_color_filter(val)]}></span>
                      <span class="text-sm">{label}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_priority_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_priority_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <!-- Category combobox -->
              <div class="relative" phx-click-away="close_category_filter">
                <button phx-click="toggle_category_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                  <div class="flex items-center gap-1.5 flex-1 min-w-0">
                    <span :if={MapSet.size(@filter_categories) == 0} class="text-base-content/60">All Categories</span>
                    <span :if={MapSet.size(@filter_categories) > 0} class="flex items-center gap-1">
                      <span class="badge badge-xs badge-primary">{MapSet.size(@filter_categories)}</span>
                      <span class="text-xs truncate">selected</span>
                    </span>
                  </div>
                  <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                </button>
                <div :if={@show_category_filter} class="absolute z-30 mt-1 w-64 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                  <div class="p-2 border-b border-base-200">
                    <form phx-change="search_category_filter">
                      <input type="text" name="query" value={@category_filter_search} placeholder="Search categories..." class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                    </form>
                  </div>
                  <div class="max-h-56 overflow-y-auto p-1">
                    <button
                      :for={cat <- filtered_ticket_categories(@all_categories, @category_filter_search)}
                      phx-click="toggle_category_item"
                      phx-value-id={cat}
                      class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_categories, cat) && "bg-primary border-primary", !MapSet.member?(@filter_categories, cat) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_categories, cat)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class={["w-2.5 h-2.5 rounded-full shrink-0", category_dot_color_filter(cat)]}></span>
                      <span class="text-sm">{String.capitalize(cat)}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_category_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_category_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <!-- Location combobox -->
              <div class="relative" phx-click-away="close_location_filter">
                <button phx-click="toggle_location_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                  <div class="flex items-center gap-1.5 flex-1 min-w-0">
                    <span :if={MapSet.size(@filter_location_ids) == 0} class="text-base-content/60">All Locations</span>
                    <span :if={MapSet.size(@filter_location_ids) > 0} class="flex items-center gap-1">
                      <span class="badge badge-xs badge-primary">{MapSet.size(@filter_location_ids)}</span>
                      <span class="text-xs truncate">selected</span>
                    </span>
                  </div>
                  <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                </button>
                <div :if={@show_location_filter} class="absolute z-30 mt-1 w-72 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                  <div class="p-2 border-b border-base-200">
                    <form phx-change="search_location_filter">
                      <input type="text" name="query" value={@location_filter_search} placeholder="Search locations..." class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                    </form>
                  </div>
                  <div class="max-h-56 overflow-y-auto p-1">
                    <button
                      :for={loc <- filtered_ticket_locations(@all_locations, @location_filter_search)}
                      phx-click="toggle_location_item"
                      phx-value-id={loc.id}
                      style={"padding-left: #{loc.depth * 16 + 8}px"}
                      class="flex items-center gap-2.5 w-full pr-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_location_ids, loc.id) && "bg-primary border-primary", !MapSet.member?(@filter_location_ids, loc.id) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_location_ids, loc.id)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class="text-sm flex-1 min-w-0 truncate">{loc.name}</span>
                      <span :if={loc.label} class="badge badge-xs badge-ghost ml-auto shrink-0">{loc.label}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_location_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_location_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <button :if={active_filter_count(assigns) > 0} phx-click="clear_all_filters" class="btn btn-xs btn-ghost text-error gap-1">
                <.icon name="hero-x-mark" class="size-3" /> Clear
              </button>
            </div>

            <!-- Row 2: Date range + Assignee -->
            <div class="grid grid-cols-2 gap-4">
              <!-- Date Range -->
              <div class="relative">
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Date Range</label>
                <button
                  type="button"
                  phx-click="toggle_date_picker"
                  class="btn btn-sm btn-ghost border border-base-300 w-full justify-start gap-2 font-normal"
                >
                  <.icon name="hero-calendar-days" class="size-4 text-base-content/40" />
                  <span :if={!@filter_date_from && !@filter_date_to} class="text-base-content/40">Select date range...</span>
                  <span :if={@filter_date_from || @filter_date_to} class="text-base-content">
                    {format_date_display(@filter_date_from)} — {format_date_display(@filter_date_to)}
                  </span>
                </button>

                <!-- Date picker dropdown -->
                <div :if={@show_date_picker} class="absolute z-30 mt-1 bg-base-100 border border-base-300 rounded-xl shadow-xl p-0 w-auto">
                  <div class="flex">
                    <!-- Presets sidebar -->
                    <div class="border-r border-base-300 py-2 w-36">
                      <button :for={{label, preset} <- date_presets()} phx-click="date_preset" phx-value-preset={preset} class="block w-full text-left px-4 py-2 text-sm text-base-content/70 hover:bg-primary/10 hover:text-primary transition-colors">
                        {label}
                      </button>
                    </div>

                    <!-- Calendar -->
                    <div class="p-4 w-72">
                      <!-- Month nav -->
                      <div class="flex items-center justify-between mb-3">
                        <button phx-click="calendar_prev_month" class="btn btn-ghost btn-xs btn-square">
                          <.icon name="hero-chevron-left" class="size-4" />
                        </button>
                        <span class="text-sm font-semibold text-base-content">
                          {Calendar.strftime(@calendar_month, "%B %Y")}
                        </span>
                        <button phx-click="calendar_next_month" class="btn btn-ghost btn-xs btn-square">
                          <.icon name="hero-chevron-right" class="size-4" />
                        </button>
                      </div>

                      <!-- Day headers -->
                      <div class="grid grid-cols-7 gap-0 mb-1">
                        <span :for={day <- ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]} class="text-center text-[10px] font-semibold text-base-content/40 py-1">
                          {day}
                        </span>
                      </div>

                      <!-- Calendar grid -->
                      <div class="grid grid-cols-7 gap-0">
                        <button
                          :for={date <- calendar_days(@calendar_month)}
                          type="button"
                          phx-click="select_calendar_date"
                          phx-value-date={Date.to_iso8601(date)}
                          class={[
                            "w-9 h-9 text-sm rounded-lg flex items-center justify-center transition-colors",
                            date.month != @calendar_month.month && "text-base-content/20",
                            date.month == @calendar_month.month && "text-base-content hover:bg-primary/10",
                            date == Date.utc_today() && "font-bold ring-1 ring-primary/30",
                            in_selected_range?(date, @filter_date_from, @filter_date_to) && "bg-primary/10",
                            is_range_endpoint?(date, @filter_date_from, @filter_date_to) && "!bg-primary !text-primary-content font-semibold"
                          ]}
                        >
                          {date.day}
                        </button>
                      </div>
                    </div>
                  </div>

                  <!-- Footer -->
                  <div class="flex items-center justify-between px-4 py-2.5 border-t border-base-300 bg-base-200/30 rounded-b-xl">
                    <div class="text-xs text-base-content/50">
                      <span :if={@filter_date_from}>{@filter_date_from}</span>
                      <span :if={@filter_date_from && @filter_date_to}> — {@filter_date_to}</span>
                      <span :if={@filter_date_from && !@filter_date_to} class="text-primary animate-pulse"> pick end date</span>
                    </div>
                    <div class="flex gap-1.5">
                      <button phx-click="clear_date_range" class="btn btn-xs btn-ghost">Clear</button>
                      <button phx-click="toggle_date_picker" class="btn btn-xs btn-primary">Done</button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Assigned To (multi-select combobox) -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Assigned To</label>
                <div class="relative">
                  <div class="flex flex-wrap gap-1.5 p-1.5 min-h-[36px] border border-base-300 rounded-lg bg-base-100 focus-within:border-primary focus-within:ring-1 focus-within:ring-primary/20">
                    <!-- Selected assignee tags -->
                    <span
                      :for={aid <- MapSet.to_list(@filter_assignee_ids)}
                      class="inline-flex items-center gap-1 px-2 py-0.5 bg-primary/10 text-primary rounded-md text-xs font-medium"
                    >
                      {assignee_name(aid, @all_assignees)}
                      <button type="button" phx-click="remove_assignee" phx-value-id={aid} class="hover:text-error">
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    </span>
                    <!-- Search input -->
                    <form phx-change="assignee_search" class="flex-1 min-w-[120px]">
                      <input
                        type="text"
                        name="query"
                        value={@assignee_search}
                        placeholder={if MapSet.size(@filter_assignee_ids) == 0, do: "Search assignees...", else: "Add more..."}
                        class="w-full border-0 bg-transparent text-sm focus:outline-none focus:ring-0 px-1 py-0.5"
                        autocomplete="off"
                        phx-debounce="150"
                      />
                    </form>
                  </div>
                  <!-- Dropdown results -->
                  <div :if={@assignee_search != ""} class="absolute z-20 mt-1 w-full bg-base-100 border border-base-300 rounded-lg shadow-lg max-h-48 overflow-y-auto">
                    <div
                      :for={a <- filtered_assignees(@all_assignees, @assignee_search, @filter_assignee_ids)}
                      phx-click="add_assignee"
                      phx-value-id={a.id}
                      class="flex items-center gap-2.5 px-3 py-2 hover:bg-base-200 cursor-pointer transition-colors"
                    >
                      <div class={[
                        "w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-semibold",
                        a.type == "user" && "bg-primary/10 text-primary",
                        a.type == "org" && "bg-warning/10 text-warning"
                      ]}>
                        {String.first(a.name) |> String.upcase()}
                      </div>
                      <div class="flex-1 min-w-0">
                        <span class="text-sm text-base-content">{a.name}</span>
                      </div>
                      <span class={[
                        "badge badge-xs",
                        a.type == "user" && "badge-primary badge-outline",
                        a.type == "org" && "badge-warning badge-outline"
                      ]}>{if a.type == "user", do: "Person", else: "Company"}</span>
                    </div>
                    <div :if={filtered_assignees(@all_assignees, @assignee_search, @filter_assignee_ids) == []} class="px-3 py-3 text-sm text-base-content/40 text-center">
                      No matches found
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- List view (flat, streamed) -->
          <div :if={@view_mode == "list"}>
            <div class="grid grid-cols-[3fr_1fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
              <span>Ticket</span><span>Status</span><span>Location</span><span>Category</span><span>Priority</span><span>Assigned To</span><span>Date</span>
            </div>
            <div id="tickets-stream" phx-update="stream">
              <.ticket_row_flat
                :for={{dom_id, ticket} <- @streams.tickets}
                id={dom_id}
                ticket={ticket}
                selected={@selected_ticket && @selected_ticket.id == ticket.id}
              />
            </div>
            <div :if={@counts.total == 0}>
              <.empty_state />
            </div>
            <!-- Infinite scroll sentinel -->
            <div
              :if={@has_more}
              id="tickets-infinite-scroll"
              phx-hook="InfiniteScroll"
              data-has-more={to_string(@has_more)}
              class="flex justify-center py-4"
            >
              <span class="loading loading-spinner loading-sm text-base-content/30"></span>
            </div>
          </div>

          <!-- Kanban view (assign-based, limited per column) -->
          <div :if={@view_mode == "kanban"} class="p-5 flex-1">
            <%= if @grouped == [] || Enum.all?(@grouped, fn {_, g} -> g.total == 0 end) do %>
              <.empty_state />
            <% else %>
              <.kanban_board grouped={@grouped} kanban_loading={@kanban_loading} selected_id={@selected_ticket && @selected_ticket.id} />
            <% end %>
          </div>
        </div>
      </div>

      <!-- Slide-over panel -->
      <.ticket_panel
        :if={@selected_ticket}
        ticket={@selected_ticket}
        comments={@comments}
        comment_body={@comment_body}
        internal_users={@internal_users}
        contractor_orgs={@contractor_orgs}
        ai_suggestions={@ai_suggestions}
        ai_loading={@ai_loading}
        location_assets={@location_assets}
      />
    </div>
    """
  end

  # ==========================================
  # SLIDE-OVER PANEL
  # ==========================================

  defp ticket_panel(assigns) do
    ~H"""
    <div class="w-full lg:w-[420px] shrink-0 bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-y-auto max-h-[calc(100vh-7rem)] animate-in slide-in-from-right">
      <!-- Panel header -->
      <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-5 py-3.5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <span class="text-base font-bold text-base-content">{@ticket.reference_number}</span>
            <.status_badge status={@ticket.status} />
          </div>
          <div class="flex items-center gap-1">
            <.link navigate={~p"/admin/tickets/#{@ticket.id}"} class="btn btn-ghost btn-xs btn-square" title="Open full page">
              <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
            </.link>
            <button phx-click="close_panel" class="btn btn-ghost btn-xs btn-square">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- Panel body -->
      <div class="p-5 space-y-5">
        <!-- Quick info rows -->
        <div class="space-y-3">
          <.info_row label="Status">
            <.status_badge status={@ticket.status} />
          </.info_row>

          <.info_row label="Priority">
            <.priority_badge priority={@ticket.priority} />
          </.info_row>

          <.info_row :if={@ticket.location} label="Location">
            <div class="flex items-center justify-end gap-1.5 text-sm text-base-content">
              <.icon name="hero-map-pin" class="size-3.5 text-base-content/40" />
              <span>{location_breadcrumb(@ticket.location)}</span>
            </div>
          </.info_row>

          <.info_row :if={@ticket.category} label="Category">
            <span class="badge badge-sm badge-ghost">{String.capitalize(@ticket.category)}</span>
          </.info_row>

          <.info_row label="Submitted">
            <span class="text-sm text-base-content/70">{Calendar.strftime(@ticket.inserted_at, "%b %d, %Y at %I:%M %p")}</span>
          </.info_row>

          <.info_row :if={@ticket.submitter_name} label="Reported by">
            <div class="flex items-center justify-end gap-2">
              <div class="w-6 h-6 rounded-full bg-base-200 flex items-center justify-center shrink-0">
                <span class="text-[10px] font-semibold text-base-content/60">
                  {String.first(@ticket.submitter_name) |> String.upcase()}
                </span>
              </div>
              <span class="text-sm text-base-content">{@ticket.submitter_name}</span>
            </div>
          </.info_row>

          <.info_row :if={@ticket.assigned_to_user} label="Assigned to">
            <div class="flex items-center justify-end gap-2">
              <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                <span class="text-[10px] font-semibold text-primary">
                  {String.first(@ticket.assigned_to_user.name || @ticket.assigned_to_user.email) |> String.upcase()}
                </span>
              </div>
              <span class="text-sm text-base-content">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
            </div>
          </.info_row>

          <.info_row :if={@ticket.sla_deadline} label="SLA Deadline">
            <span
              id={"sla-timer-#{@ticket.id}"}
              phx-hook="SLATimer"
              data-deadline={DateTime.to_iso8601(@ticket.sla_deadline)}
              data-paused={to_string(not is_nil(@ticket.sla_paused_at))}
              class={["text-sm font-medium", sla_color(@ticket)]}
            >
              {sla_text(@ticket)}
            </span>
          </.info_row>
        </div>

        <!-- Description -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Description</p>
          <p class="text-sm text-base-content leading-relaxed bg-base-200/40 rounded-lg p-3">
            {@ticket.description}
          </p>
        </div>

        <!-- Priority selector -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Set Priority</p>
          <div class="grid grid-cols-4 gap-1.5">
            <button
              :for={{p, label, color} <- [{"emergency", "Urgent", "btn-error"}, {"high", "High", "btn-warning"}, {"medium", "Medium", "btn-ghost border-amber-300"}, {"low", "Low", "btn-ghost"}]}
              phx-click="set_priority"
              phx-value-priority={p}
              class={["btn btn-xs", @ticket.priority == p && color, @ticket.priority != p && "btn-ghost opacity-60"]}
            >
              {label}
            </button>
          </div>
        </div>

        <!-- Category selector -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Category</p>
          <form phx-change="set_category">
            <select name="category" class="select select-sm select-bordered w-full">
              <option value="">-- No category --</option>
              <option
                :for={cat <- ["hvac", "plumbing", "electrical", "structural", "appliance", "furniture", "it", "other"]}
                value={cat}
                selected={@ticket.category == cat}
              >
                {String.capitalize(cat)}
              </option>
            </select>
          </form>
        </div>

        <!-- Linked Asset -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Linked Asset</p>
          <%= if @ticket.location do %>
            <form phx-change="link_asset">
              <select name="asset_id" class="select select-sm select-bordered w-full">
                <option value="">-- Link to asset --</option>
                <option
                  :for={asset <- @location_assets}
                  value={asset.id}
                  selected={Enum.any?(Fixly.Assets.list_links_for_ticket(@ticket.id), fn l -> l.asset_id == asset.id end)}
                >
                  {asset.name}
                </option>
              </select>
            </form>
          <% else %>
            <p class="text-xs text-base-content/40 italic">No location set — cannot link assets</p>
          <% end %>
        </div>

        <!-- Assignment -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Assignment</p>
          <div class="space-y-2">
            <form phx-change="assign_to_org">
              <select class="select select-bordered select-sm w-full" name="org_id">
                <option value="">— Assign to contractor —</option>
                <option :for={org <- @contractor_orgs} value={org.id} selected={@ticket.assigned_to_org_id == org.id}>
                  {org.name}
                </option>
              </select>
            </form>
            <form phx-change="assign_to_user">
              <select class="select select-bordered select-sm w-full" name="user_id">
                <option value="">— Assign to technician —</option>
                <option :for={user <- @internal_users} value={user.id} selected={@ticket.assigned_to_user_id == user.id}>
                  {user.name || user.email}
                </option>
              </select>
            </form>
          </div>
        </div>

        <!-- Status actions -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Actions</p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={{s, label, icon} <- status_actions(@ticket.status)}
              phx-click="update_status"
              phx-value-status={s}
              class="btn btn-sm btn-outline gap-1.5"
            >
              <.icon name={icon} class="size-3.5" />
              {label}
            </button>
          </div>
        </div>

        <!-- Navigate to location -->
        <!-- AI + Navigate -->
        <div class="flex gap-2">
          <button
            phx-click="analyze_with_ai"
            class="btn btn-sm btn-outline btn-accent flex-1 gap-2"
          >
            <.icon name="hero-sparkles" class="size-4" />
            Analyze with AI
          </button>
          <a
            :if={@ticket.location}
            href={maps_url(@ticket)}
            target="_blank"
            class="btn btn-sm btn-outline flex-1 gap-2"
          >
            <.icon name="hero-map-pin" class="size-4" />
            Navigate
          </a>
        </div>

        <!-- AI Loading indicator -->
        <div :if={@ai_loading} class="flex items-center gap-2 px-3 py-2 bg-accent/5 border border-accent/20 rounded-lg">
          <span class="loading loading-spinner loading-xs text-accent"></span>
          <span class="text-xs text-accent">Analyzing ticket with AI...</span>
        </div>

        <!-- AI Suggestions -->
        <div :if={@ai_suggestions != []} class="space-y-3">
          <p class="text-xs font-semibold text-accent uppercase tracking-wider mb-2 flex items-center gap-1.5">
            <.icon name="hero-sparkles" class="size-3.5" /> AI Suggestions
          </p>

          <div :for={suggestion <- @ai_suggestions} class="bg-accent/5 border border-accent/20 rounded-lg p-3 space-y-2">
            <!-- Type badge + confidence -->
            <div class="flex items-center justify-between">
              <span class={[
                "badge badge-sm font-medium",
                suggestion.suggestion_type in ["category", "priority"] && "badge-info badge-outline",
                suggestion.suggestion_type == "create_asset" && "badge-success badge-outline",
                suggestion.suggestion_type == "link_asset" && "badge-warning badge-outline"
              ]}>
                {suggestion_type_label(suggestion.suggestion_type)}
              </span>
              <div class="flex items-center gap-1.5">
                <div class="w-16 h-1.5 rounded-full bg-base-300 overflow-hidden">
                  <div
                    class={[
                      "h-full rounded-full",
                      suggestion.confidence && suggestion.confidence >= 0.8 && "bg-success",
                      suggestion.confidence && suggestion.confidence >= 0.6 && suggestion.confidence < 0.8 && "bg-warning",
                      (is_nil(suggestion.confidence) || suggestion.confidence < 0.6) && "bg-error"
                    ]}
                    style={"width: #{(suggestion.confidence || 0) * 100}%"}
                  >
                  </div>
                </div>
                <span class="text-[10px] text-base-content/50">{round((suggestion.confidence || 0) * 100)}%</span>
              </div>
            </div>

            <!-- Suggested value -->
            <div class="text-sm font-semibold text-base-content">
              {suggestion_display_value(suggestion)}
            </div>

            <!-- Reasoning -->
            <p :if={suggestion.reasoning} class="text-xs text-base-content/60 leading-relaxed">
              {suggestion.reasoning}
            </p>

            <!-- Action buttons -->
            <div class="flex gap-1.5 pt-1">
              <button
                phx-click="apply_suggestion"
                phx-value-id={suggestion.id}
                class="btn btn-xs btn-success btn-outline gap-1"
              >
                <.icon name="hero-check" class="size-3" /> Apply
              </button>
              <button
                phx-click="dismiss_suggestion"
                phx-value-id={suggestion.id}
                class="btn btn-xs btn-ghost gap-1 text-base-content/50"
              >
                <.icon name="hero-x-mark" class="size-3" /> Dismiss
              </button>
            </div>
          </div>
        </div>

        <!-- Activity Timeline / Discussion -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider">
              Activity
              <span :if={@comments != []} class="ml-1 badge badge-xs badge-ghost">{length(@comments)}</span>
            </p>
          </div>

          <div class="space-y-2 mb-3 max-h-80 overflow-y-auto">
            <%= for comment <- @comments do %>
              <%= if comment.type in ["comment", nil] do %>
                <%!-- Chat bubble for regular comments --%>
                <div class="flex gap-2.5">
                  <div class="w-7 h-7 rounded-full bg-base-200 flex items-center justify-center shrink-0 mt-0.5">
                    <span class="text-[10px] font-semibold text-base-content/50">
                      {comment_initials(comment)}
                    </span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-0.5">
                      <span class="text-xs font-semibold text-base-content">{comment_author(comment)}</span>
                      <span class="text-[10px] text-base-content/40">{Calendar.strftime(comment.inserted_at, "%b %d %I:%M %p")}</span>
                    </div>
                    <div class="bg-base-100 border border-base-300 rounded-lg rounded-tl-none px-3 py-2">
                      <p class="text-sm text-base-content/70 leading-relaxed">{comment.body}</p>
                    </div>
                  </div>
                </div>
              <% else %>
                <%!-- System event (status_change, assignment, priority_change, etc.) --%>
                <div class="flex items-center gap-2 py-1.5 px-2">
                  <div class={[
                    "w-5 h-5 rounded-full flex items-center justify-center shrink-0",
                    timeline_event_dot_bg(comment.type)
                  ]}>
                    <.icon name={timeline_event_icon(comment.type)} class={["size-2.5", timeline_event_icon_color(comment.type)]} />
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class={[
                      "text-xs leading-relaxed",
                      comment.type == "sla_breach" && "text-error font-semibold",
                      comment.type != "sla_breach" && "text-base-content/50"
                    ]}>
                      {timeline_event_text(comment)}
                    </p>
                  </div>
                  <span class="text-[9px] text-base-content/30 shrink-0">{Calendar.strftime(comment.inserted_at, "%b %d %I:%M %p")}</span>
                </div>
              <% end %>
            <% end %>
            <p :if={@comments == []} class="text-xs text-base-content/40 text-center py-3">No activity yet</p>
          </div>

          <form phx-submit="add_comment" class="flex gap-2">
            <input
              type="text"
              name="body"
              value={@comment_body}
              placeholder="Add a comment..."
              class="input input-sm input-bordered flex-1"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-sm btn-primary">
              <.icon name="hero-paper-airplane" class="size-3.5" />
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # Info row for the panel
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp info_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <span class="text-xs text-base-content/50 shrink-0 w-24">{@label}</span>
      <div class="flex-1 text-right">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ==========================================
  # STAT CARD
  # ==========================================

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "primary"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-base-content/60">{@label}</p>
          <p class="text-2xl font-bold text-base-content mt-1">{@value}</p>
        </div>
        <div class={["w-11 h-11 rounded-xl flex items-center justify-center", "bg-#{@color}/10"]}>
          <.icon name={@icon} class={["size-5", "text-#{@color}"]} />
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # FLAT TABLE ROW (for streamed list view)
  # ==========================================

  attr :id, :string, required: true
  attr :ticket, Ticket, required: true
  attr :selected, :boolean, default: false

  defp ticket_row_flat(assigns) do
    ~H"""
    <div
      id={@id}
      phx-click="select_ticket"
      phx-value-id={@ticket.id}
      class={[
        "grid grid-cols-[3fr_1fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center cursor-pointer transition-colors",
        @selected && "bg-primary/5 border-l-2 border-l-primary",
        !@selected && "hover:bg-base-200/30"
      ]}
    >
      <div class="min-w-0">
        <p class="text-sm font-medium text-base-content truncate">{truncate(@ticket.description, 60)}</p>
        <p class="text-xs text-base-content/50 mt-0.5">
          {@ticket.reference_number}
          <span :if={@ticket.submitter_name}> · {@ticket.submitter_name}</span>
        </p>
      </div>
      <div><.status_badge status={@ticket.status} /></div>
      <div class="min-w-0">
        <p :if={@ticket.location} class="text-sm text-base-content/70 truncate">{@ticket.location.name}</p>
        <p :if={!@ticket.location} class="text-sm text-base-content/30">—</p>
      </div>
      <div>
        <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
        <span :if={!@ticket.category} class="text-sm text-base-content/30">—</span>
      </div>
      <div><.priority_badge priority={@ticket.priority} /></div>
      <div class="min-w-0">
        <span :if={@ticket.assigned_to_user} class="text-sm text-base-content/70 truncate">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
        <span :if={!@ticket.assigned_to_user && @ticket.assigned_to_org} class="text-sm text-base-content/50 truncate">{@ticket.assigned_to_org.name}</span>
        <span :if={!@ticket.assigned_to_user && !@ticket.assigned_to_org} class="text-xs text-base-content/30">Unassigned</span>
      </div>
      <div><p class="text-sm text-base-content/60">{format_date(@ticket.inserted_at)}</p></div>
    </div>
    """
  end

  # ==========================================
  # KANBAN BOARD
  # ==========================================

  attr :grouped, :list, required: true
  attr :kanban_loading, :any, required: true
  attr :selected_id, :string, default: nil

  defp kanban_board(assigns) do
    ~H"""
    <div class="flex gap-4 overflow-x-auto pb-4 items-stretch min-h-[400px]">
      <.kanban_column
        :for={{status, group_data} <- @grouped}
        status={status}
        tickets={group_data.tickets}
        total={group_data.total}
        has_more={group_data.has_more}
        loading={MapSet.member?(@kanban_loading, status)}
        selected_id={@selected_id}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :total, :integer, required: true
  attr :has_more, :boolean, required: true
  attr :loading, :boolean, default: false
  attr :selected_id, :string, default: nil

  defp kanban_column(assigns) do
    assigns = assign(assigns, :indexed_tickets, Enum.with_index(assigns.tickets, 1))

    ~H"""
    <div
      class="flex-shrink-0 w-72 flex flex-col"
      id={"kanban-col-#{@status}"}
      phx-hook="KanbanDrop"
      data-status={@status}
    >
      <div class="flex items-center gap-2 mb-3">
        <div class={["w-2 h-2 rounded-full", status_dot_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">{status_label(@status)}</span>
        <span class="badge badge-sm badge-ghost">{@total}</span>
      </div>
      <div class="space-y-2.5 flex-1 min-h-[200px] max-h-[calc(100vh-16rem)] overflow-y-auto kanban-dropzone rounded-lg transition-colors p-1" id={"kanban-scroll-#{@status}"}>
        <.kanban_card :for={{ticket, idx} <- @indexed_tickets} ticket={ticket} index={idx} selected={@selected_id == ticket.id} />
        <!-- Loading spinner -->
        <div :if={@loading} class="flex justify-center py-3">
          <span class="loading loading-spinner loading-sm text-primary"></span>
        </div>
        <!-- Infinite scroll sentinel (auto-loads when visible) -->
        <div
          :if={@has_more && !@loading}
          id={"kanban-sentinel-#{@status}"}
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          data-event="load_more_in_group"
          data-param-status={@status}
          data-scroll-root=".kanban-dropzone"
          class="h-1"
        />
      </div>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :index, :integer, required: true
  attr :selected, :boolean, default: false

  defp kanban_card(assigns) do
    ~H"""
    <div
      phx-click="select_ticket"
      phx-value-id={@ticket.id}
      draggable="true"
      data-ticket-id={@ticket.id}
      class={[
        "rounded-lg border p-3.5 shadow-sm cursor-grab active:cursor-grabbing transition-all kanban-card",
        @selected && "border-primary bg-primary/5 shadow-md ring-1 ring-primary/20",
        !@selected && "border-base-300 bg-base-100 hover:shadow-md"
      ]}
    >
      <div class="flex items-start justify-between gap-2 mb-2">
        <div class="flex items-center gap-1.5">
          <span class="text-[10px] font-mono text-base-content/25 w-5 shrink-0">{@index}</span>
          <div class="flex flex-wrap gap-1.5">
            <.priority_badge :if={@ticket.priority} priority={@ticket.priority} />
            <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
          </div>
        </div>
        <span class="text-xs text-base-content/40 font-mono shrink-0">{@ticket.reference_number}</span>
      </div>
      <p class="text-sm font-medium text-base-content leading-snug mb-2">{truncate(@ticket.description, 80)}</p>
      <div :if={@ticket.location} class="flex items-center gap-1 text-xs text-base-content/50 mb-3">
        <.icon name="hero-map-pin" class="size-3" />
        <span class="truncate">{@ticket.location.name}</span>
      </div>
      <div class="flex items-center justify-between">
        <div :if={@ticket.assigned_to_user} class="flex items-center gap-1.5">
          <div class="w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center">
            <span class="text-[9px] font-semibold text-primary">
              {String.first(@ticket.assigned_to_user.name || @ticket.assigned_to_user.email) |> String.upcase()}
            </span>
          </div>
        </div>
        <span :if={!@ticket.assigned_to_user} class="text-[10px] text-base-content/30">Unassigned</span>
        <span class="text-xs text-base-content/40">{format_date(@ticket.inserted_at)}</span>
      </div>
    </div>
    """
  end

  # ==========================================
  # SHARED COMPONENTS
  # ==========================================

  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :value, :string, required: true

  defp filter_chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 px-2.5 py-1 bg-base-200 rounded-full text-xs font-medium text-base-content/70">
      {@label}
      <button type="button" phx-click={@event} phx-value-id={@value} class="text-base-content/40 hover:text-error transition-colors">
        <.icon name="hero-x-mark" class="size-3" />
      </button>
    </span>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
        <.icon name="hero-ticket" class="size-7 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content mb-1">No tickets yet</h3>
      <p class="text-sm text-base-content/50 max-w-xs">Tickets will appear here when residents scan a QR code and submit a maintenance request.</p>
    </div>
    """
  end

  attr :status, :string, required: true
  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm font-medium", status_badge_class(@status)]}>{status_label(@status)}</span>
    """
  end

  attr :priority, :string, default: nil
  defp priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={["badge badge-sm font-medium", priority_badge_class(@priority)]}>
      <span class={["w-1.5 h-1.5 rounded-full mr-1.5", priority_dot_class(@priority)]}></span>
      {String.capitalize(@priority)}
    </span>
    <span :if={!@priority} class="text-xs text-base-content/30">—</span>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true
  def handle_event("select_ticket", %{"id" => id}, socket) do
    # If clicking the same ticket, close the panel
    if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == id do
      {:noreply, assign(socket, selected_ticket: nil, comments: [], ai_suggestions: [], location_assets: [])}
    else
      ticket = Tickets.get_ticket!(id)
      require Logger
      Logger.info("SELECT_TICKET #{ticket.reference_number}: org=#{inspect(ticket.assigned_to_org_id)}, user=#{inspect(ticket.assigned_to_user_id)}")
      comments = Tickets.list_comments(id)
      ai_suggestions = AI.list_suggestions_for_ticket(id)
      location_assets = if ticket.location_id, do: Assets.list_assets_for_location(ticket.location_id), else: []
      {:noreply, assign(socket, selected_ticket: ticket, comments: comments, comment_body: "", ai_suggestions: ai_suggestions, location_assets: location_assets)}
    end
  end

  def handle_event("close_panel", _, socket) do
    {:noreply, assign(socket, selected_ticket: nil, comments: [], ai_suggestions: [], location_assets: [])}
  end

  # --- Load more (per-group pagination for kanban) ---

  def handle_event("load_more_in_group", %{"status" => status}, socket) do
    grouped = socket.assigns.grouped

    # Prevent duplicate loads if already loading
    if MapSet.member?(socket.assigns.kanban_loading, status) do
      {:noreply, socket}
    else
      case Enum.find(grouped, fn {s, _} -> s == status end) do
        {^status, group_data} when group_data.has_more ->
          # Show loading state
          socket = assign(socket, :kanban_loading, MapSet.put(socket.assigns.kanban_loading, status))

          current_count = length(group_data.tickets)
          filters = build_filters(socket.assigns)
          more_tickets = Tickets.list_tickets_for_status(socket.assigns.org_id, status, filters, current_count, 20)

          updated_tickets = group_data.tickets ++ more_tickets
          new_has_more = length(updated_tickets) < group_data.total

          updated_grouped =
            Enum.map(grouped, fn
              {^status, gd} -> {status, %{gd | tickets: updated_tickets, has_more: new_has_more}}
              other -> other
            end)

          {:noreply,
           socket
           |> assign(:grouped, updated_grouped)
           |> assign(:kanban_loading, MapSet.delete(socket.assigns.kanban_loading, status))}

        _ ->
          {:noreply, socket}
      end
    end
  end

  # --- Infinite scroll (kept for assets, unused by tickets now) ---

  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      filters = build_filters(socket.assigns)
      page = Tickets.list_tickets_paginated(socket.assigns.org_id, filters, socket.assigns.cursor)

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:tickets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> reload_data()}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, socket |> assign(:search_query, "") |> reload_data()}
  end

  # --- Kanban Drag & Drop ---

  def handle_event("kanban_drop", %{"ticket_id" => ticket_id, "new_status" => new_status}, socket) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = socket.assigns.current_user

    if ticket.status == new_status do
      {:noreply, socket}
    else
      case Tickets.update_ticket_status(ticket, new_status, user) do
        {:ok, _} ->
          Tickets.log_ticket_event(ticket.id, "status_change", "Status changed from #{status_label(ticket.status)} to #{status_label(new_status)}", %{from: ticket.status, to: new_status, changed_by: user.name || user.email})

          updated = Tickets.get_ticket!(ticket.id)
          PubSubBroadcast.broadcast_ticket_updated(updated)

          socket =
            if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == ticket_id do
              assign(socket, :selected_ticket, updated)
            else
              socket
            end

          {:noreply, reload_data(socket)}

        {:error, :unauthorized_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot move ticket from #{status_label(ticket.status)} to #{status_label(new_status)}")}

        {:error, :proof_required} ->
          {:noreply, put_flash(socket, :error, "Proof of completion required before marking as completed")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update status")}
      end
    end
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, socket |> assign(:view_mode, mode) |> reload_data()}
  end

  def handle_event("toggle_filters", _, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  # --- Status filter combobox ---
  def handle_event("toggle_status_filter", _, socket) do
    {:noreply, assign(socket, :show_status_filter, !socket.assigns.show_status_filter)}
  end

  def handle_event("close_status_filter", _, socket) do
    {:noreply, assign(socket, show_status_filter: false, status_filter_search: "")}
  end

  def handle_event("search_status_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :status_filter_search, query)}
  end

  def handle_event("toggle_status_item", %{"id" => val}, socket) do
    statuses = socket.assigns.filter_statuses
    statuses = if MapSet.member?(statuses, val), do: MapSet.delete(statuses, val), else: MapSet.put(statuses, val)
    {:noreply, socket |> assign(:filter_statuses, statuses) |> reload_data()}
  end

  def handle_event("clear_status_filter", _, socket) do
    {:noreply, socket |> assign(filter_statuses: MapSet.new(), status_filter_search: "") |> reload_data()}
  end

  # --- Priority filter combobox ---
  def handle_event("toggle_priority_filter", _, socket) do
    {:noreply, assign(socket, :show_priority_filter, !socket.assigns.show_priority_filter)}
  end

  def handle_event("close_priority_filter", _, socket) do
    {:noreply, assign(socket, show_priority_filter: false, priority_filter_search: "")}
  end

  def handle_event("search_priority_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :priority_filter_search, query)}
  end

  def handle_event("toggle_priority_item", %{"id" => val}, socket) do
    priorities = socket.assigns.filter_priorities
    priorities = if MapSet.member?(priorities, val), do: MapSet.delete(priorities, val), else: MapSet.put(priorities, val)
    {:noreply, socket |> assign(:filter_priorities, priorities) |> reload_data()}
  end

  def handle_event("clear_priority_filter", _, socket) do
    {:noreply, socket |> assign(filter_priorities: MapSet.new(), priority_filter_search: "") |> reload_data()}
  end

  # --- Category filter combobox ---
  def handle_event("toggle_category_filter", _, socket) do
    {:noreply, assign(socket, :show_category_filter, !socket.assigns.show_category_filter)}
  end

  def handle_event("close_category_filter", _, socket) do
    {:noreply, assign(socket, show_category_filter: false, category_filter_search: "")}
  end

  def handle_event("search_category_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :category_filter_search, query)}
  end

  def handle_event("toggle_category_item", %{"id" => val}, socket) do
    categories = socket.assigns.filter_categories
    categories = if MapSet.member?(categories, val), do: MapSet.delete(categories, val), else: MapSet.put(categories, val)
    {:noreply, socket |> assign(:filter_categories, categories) |> reload_data()}
  end

  def handle_event("clear_category_filter", _, socket) do
    {:noreply, socket |> assign(filter_categories: MapSet.new(), category_filter_search: "") |> reload_data()}
  end

  # --- Location filter combobox ---
  def handle_event("toggle_location_filter", _, socket) do
    {:noreply, assign(socket, :show_location_filter, !socket.assigns.show_location_filter)}
  end

  def handle_event("close_location_filter", _, socket) do
    {:noreply, assign(socket, show_location_filter: false, location_filter_search: "")}
  end

  def handle_event("search_location_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :location_filter_search, query)}
  end

  def handle_event("toggle_location_item", %{"id" => val}, socket) do
    location_ids = socket.assigns.filter_location_ids
    location_ids = if MapSet.member?(location_ids, val), do: MapSet.delete(location_ids, val), else: MapSet.put(location_ids, val)
    {:noreply, socket |> assign(:filter_location_ids, location_ids) |> reload_data()}
  end

  def handle_event("clear_location_filter", _, socket) do
    {:noreply, socket |> assign(filter_location_ids: MapSet.new(), location_filter_search: "") |> reload_data()}
  end

  # --- Date Range Picker ---

  def handle_event("toggle_date_picker", _, socket) do
    {:noreply, assign(socket, :show_date_picker, !socket.assigns.show_date_picker)}
  end

  def handle_event("calendar_prev_month", _, socket) do
    new_month = Date.add(socket.assigns.calendar_month, -30)
    new_month = Date.new!(new_month.year, new_month.month, 1)
    {:noreply, assign(socket, :calendar_month, new_month)}
  end

  def handle_event("calendar_next_month", _, socket) do
    days_in_month = Date.days_in_month(socket.assigns.calendar_month)
    new_month = Date.add(socket.assigns.calendar_month, days_in_month)
    new_month = Date.new!(new_month.year, new_month.month, 1)
    {:noreply, assign(socket, :calendar_month, new_month)}
  end

  def handle_event("select_calendar_date", %{"date" => date_str}, socket) do
    {:ok, date} = Date.from_iso8601(date_str)
    date_s = Date.to_iso8601(date)

    {from, to} =
      cond do
        # No start date yet — set as start
        is_nil(socket.assigns.filter_date_from) ->
          {date_s, nil}

        # Start date set but no end — set as end (swap if before start)
        is_nil(socket.assigns.filter_date_to) ->
          {:ok, start} = Date.from_iso8601(socket.assigns.filter_date_from)
          if Date.compare(date, start) == :lt do
            {date_s, socket.assigns.filter_date_from}
          else
            {socket.assigns.filter_date_from, date_s}
          end

        # Both set — start new selection
        true ->
          {date_s, nil}
      end

    {:noreply, socket |> assign(filter_date_from: from, filter_date_to: to) |> reload_data()}
  end

  def handle_event("date_preset", %{"preset" => preset}, socket) do
    today = Date.utc_today()

    {from, to} =
      case preset do
        "today" -> {Date.to_iso8601(today), Date.to_iso8601(today)}
        "7d" -> {Date.to_iso8601(Date.add(today, -7)), Date.to_iso8601(today)}
        "14d" -> {Date.to_iso8601(Date.add(today, -14)), Date.to_iso8601(today)}
        "30d" -> {Date.to_iso8601(Date.add(today, -30)), Date.to_iso8601(today)}
        "90d" -> {Date.to_iso8601(Date.add(today, -90)), Date.to_iso8601(today)}
        "mtd" -> {Date.to_iso8601(Date.new!(today.year, today.month, 1)), Date.to_iso8601(today)}
        "ytd" -> {Date.to_iso8601(Date.new!(today.year, 1, 1)), Date.to_iso8601(today)}
        "all" -> {nil, nil}
        _ -> {nil, nil}
      end

    {:noreply, socket |> assign(filter_date_from: from, filter_date_to: to, show_date_picker: false) |> reload_data()}
  end

  def handle_event("clear_date_range", _, socket) do
    {:noreply, socket |> assign(filter_date_from: nil, filter_date_to: nil) |> reload_data()}
  end

  def handle_event("assignee_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :assignee_search, query)}
  end

  def handle_event("add_assignee", %{"id" => id}, socket) do
    ids = MapSet.put(socket.assigns.filter_assignee_ids, id)
    {:noreply, socket |> assign(filter_assignee_ids: ids, assignee_search: "") |> reload_data()}
  end

  def handle_event("remove_assignee", %{"id" => id}, socket) do
    ids = MapSet.delete(socket.assigns.filter_assignee_ids, id)
    {:noreply, socket |> assign(:filter_assignee_ids, ids) |> reload_data()}
  end

  def handle_event("clear_filter", %{"id" => "date_range"}, socket) do
    {:noreply, socket |> assign(filter_date_from: nil, filter_date_to: nil) |> reload_data()}
  end

  def handle_event("clear_all_filters", _, socket) do
    {:noreply,
     socket
     |> assign(
       filter_statuses: MapSet.new(),
       filter_priorities: MapSet.new(),
       filter_categories: MapSet.new(),
       filter_location_ids: MapSet.new(),
       filter_date_from: nil,
       filter_date_to: nil,
       filter_assignee_ids: MapSet.new(),
       assignee_search: "",
       search_query: "",
       status_filter_search: "",
       priority_filter_search: "",
       category_filter_search: "",
       location_filter_search: ""
     )
     |> reload_data()}
  end

  def handle_event("analyze_with_ai", _, socket) do
    ticket = socket.assigns.selected_ticket

    case Fixly.Workers.AITicketWorker.enqueue(ticket.id) do
      {:ok, _job} ->
        # Schedule periodic checks to pick up suggestions when the AI job completes
        Process.send_after(self(), :refresh_ai_suggestions, 3_000)
        Process.send_after(self(), :refresh_ai_suggestions, 8_000)
        Process.send_after(self(), :refresh_ai_suggestions, 15_000)

        {:noreply,
         socket
         |> assign(:ai_loading, true)
         |> put_flash(:info, "AI analysis queued for #{ticket.reference_number}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to queue AI analysis")}
    end
  end

  def handle_event("set_priority", %{"priority" => priority}, socket) do
    old_priority = socket.assigns.selected_ticket.priority
    {:ok, ticket} = Tickets.set_priority(socket.assigns.selected_ticket, priority)
    ticket = Tickets.get_ticket!(ticket.id)
    user = socket.assigns.current_user
    Tickets.log_ticket_event(ticket.id, "priority_change", "Priority changed to #{priority}", %{
      from: old_priority,
      to: priority,
      changed_by: user.name || user.email
    })
    PubSubBroadcast.broadcast_ticket_updated(ticket)
    {:noreply, socket |> assign(selected_ticket: ticket) |> reload_data()}
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    ticket = socket.assigns.selected_ticket
    user = socket.assigns.current_user

    case Tickets.update_ticket_status(ticket, status, user) do
      {:ok, _} ->
        Tickets.log_ticket_event(ticket.id, "status_change", "Status changed from #{status_label(ticket.status)} to #{status_label(status)}", %{
          from: ticket.status,
          to: status,
          changed_by: user.name || user.email
        })
        updated = Tickets.get_ticket!(ticket.id)
        PubSubBroadcast.broadcast_ticket_updated(updated)
        {:noreply, socket |> assign(selected_ticket: updated) |> reload_data()}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot change status from #{status_label(ticket.status)} to #{status_label(status)}")}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Proof of completion required before marking as completed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("assign_to_org", params, socket) do
    require Logger
    org_id = params["org_id"]
    ticket = socket.assigns.selected_ticket
    current_org_id = ticket.assigned_to_org_id || ""
    user = socket.assigns.current_user
    Logger.info("ASSIGN_TO_ORG: org_id=#{inspect(org_id)}, current=#{inspect(current_org_id)}, ticket=#{ticket.reference_number}")

    # Skip if nothing changed (prevents re-render loops)
    if org_id == current_org_id do
      Logger.info("ASSIGN_TO_ORG: SKIPPED (no change)")
      {:noreply, socket}
    else
      if org_id == "" || is_nil(org_id) do
        {:ok, _} = Tickets.update_ticket(ticket, %{assigned_to_org_id: nil})
      else
        {:ok, _} = Tickets.assign_ticket(ticket, %{assigned_to_org_id: org_id})
        org_name = Enum.find(socket.assigns.contractor_orgs, fn o -> o.id == org_id end)
        org_name = if org_name, do: org_name.name, else: "contractor"
        Tickets.log_ticket_event(ticket.id, "assignment", "Assigned to #{org_name}", %{
          assigned_to: org_name,
          assigned_by: user.name || user.email,
          org_name: org_name
        })
      end

      updated = Tickets.get_ticket!(ticket.id)
      PubSubBroadcast.broadcast_ticket_updated(updated)
      {:noreply, socket |> assign(selected_ticket: updated) |> reload_data()}
    end
  end

  def handle_event("assign_to_user", params, socket) do
    user_id = params["user_id"]
    ticket = socket.assigns.selected_ticket
    current_user_id = ticket.assigned_to_user_id || ""
    admin_user = socket.assigns.current_user

    # Skip if nothing changed (prevents re-render loops)
    if user_id == current_user_id do
      {:noreply, socket}
    else
      if user_id == "" || is_nil(user_id) do
        {:ok, _} = Tickets.update_ticket(ticket, %{assigned_to_user_id: nil})
      else
        {:ok, _} = Tickets.assign_ticket(ticket, %{assigned_to_user_id: user_id})
        tech = Enum.find(socket.assigns.internal_users, fn u -> u.id == user_id end)
        tech_name = if tech, do: tech.name || tech.email, else: "technician"
        Tickets.log_ticket_event(ticket.id, "assignment", "Assigned to #{tech_name}", %{
          assigned_to: tech_name,
          assigned_by: admin_user.name || admin_user.email
        })
      end

      updated = Tickets.get_ticket!(ticket.id)
      PubSubBroadcast.broadcast_ticket_updated(updated)
      {:noreply, socket |> assign(selected_ticket: updated) |> reload_data()}
    end
  end

  def handle_event("add_comment", %{"body" => body}, socket) when byte_size(body) > 0 do
    user = socket.assigns.current_user
    ticket = socket.assigns.selected_ticket

    {:ok, comment} = Tickets.create_comment(%{
      ticket_id: ticket.id,
      user_id: user.id,
      body: body
    })

    PubSubBroadcast.broadcast_comment_added(ticket, comment)
    comments = Tickets.list_comments(ticket.id)
    {:noreply, assign(socket, comments: comments, comment_body: "")}
  end

  def handle_event("add_comment", _, socket), do: {:noreply, socket}

  # --- Category ---

  def handle_event("set_category", %{"category" => category}, socket) do
    ticket = socket.assigns.selected_ticket
    cat_value = if category == "", do: nil, else: category

    # Skip if nothing changed
    if cat_value == ticket.category do
      {:noreply, socket}
    else
      {:ok, _} = Tickets.update_ticket(ticket, %{category: cat_value})
      updated = Tickets.get_ticket!(ticket.id)
      Tickets.log_ticket_event(ticket.id, "category_change", "Category changed to #{category || "none"}", %{
        from: ticket.category,
        to: cat_value
      })
      PubSubBroadcast.broadcast_ticket_updated(updated)
      {:noreply, socket |> assign(selected_ticket: updated) |> reload_data()}
    end
  end

  # --- Asset linking ---

  def handle_event("link_asset", %{"asset_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("link_asset", %{"asset_id" => asset_id}, socket) do
    ticket = socket.assigns.selected_ticket
    asset = Assets.get_asset!(asset_id)

    case Assets.link_ticket_to_asset(ticket.id, asset_id, "manual") do
      {:ok, _link} ->
        Tickets.log_ticket_event(ticket.id, "asset_linked", "Asset \"#{asset.name}\" linked to this ticket", %{
          asset_name: asset.name,
          asset_id: asset_id
        })
        updated = Tickets.get_ticket!(ticket.id)
        PubSubBroadcast.broadcast_ticket_updated(updated)
        {:noreply, socket |> assign(selected_ticket: updated) |> reload_data()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to link asset (may already be linked)")}
    end
  end

  # --- AI Suggestion actions ---

  def handle_event("apply_suggestion", %{"id" => suggestion_id}, socket) do
    suggestion = AI.get_suggestion!(suggestion_id)
    user = socket.assigns.current_user
    ticket = socket.assigns.selected_ticket

    result =
      case suggestion.suggestion_type do
        "category" ->
          cat = suggestion.suggested_data["category"]
          {:ok, _} = Tickets.update_ticket(ticket, %{category: cat})
          Tickets.log_activity(ticket.id, "system", "Category set to #{cat} (AI suggestion)")
          :ok

        "priority" ->
          priority = suggestion.suggested_data["priority"]
          {:ok, _} = Tickets.set_priority(ticket, priority)
          Tickets.log_activity(ticket.id, "system", "Priority set to #{priority} (AI suggestion)")
          :ok

        "create_asset" ->
          data = suggestion.suggested_data
          asset_attrs = %{
            name: data["name"],
            category: data["category"],
            location_id: ticket.location_id,
            organization_id: ticket.organization_id,
            created_via: "ai",
            ai_confidence: suggestion.confidence
          }

          case Assets.create_asset(asset_attrs) do
            {:ok, asset} ->
              Assets.link_ticket_to_asset(ticket.id, asset.id, "ai")
              Tickets.log_activity(ticket.id, "system", "Asset '#{asset.name}' created and linked (AI suggestion)")
              :ok

            {:error, _} ->
              :error
          end

        "link_asset" ->
          asset_id = suggestion.suggested_data["asset_id"]

          case Assets.link_ticket_to_asset(ticket.id, asset_id, "ai") do
            {:ok, _} ->
              Tickets.log_activity(ticket.id, "system", "Asset linked (AI suggestion)")
              :ok

            {:error, _} ->
              :error
          end
      end

    case result do
      :ok ->
        AI.approve_suggestion(suggestion, user.id)
        updated = Tickets.get_ticket!(ticket.id)
        suggestions = AI.list_suggestions_for_ticket(ticket.id)
        location_assets = if updated.location_id, do: Assets.list_assets_for_location(updated.location_id), else: []
        PubSubBroadcast.broadcast_ticket_updated(updated)

        {:noreply,
         socket
         |> assign(selected_ticket: updated, ai_suggestions: suggestions, location_assets: location_assets)
         |> reload_data()
         |> put_flash(:info, "AI suggestion applied")}

      :error ->
        {:noreply, put_flash(socket, :error, "Failed to apply suggestion")}
    end
  end

  def handle_event("dismiss_suggestion", %{"id" => suggestion_id}, socket) do
    suggestion = AI.get_suggestion!(suggestion_id)
    user = socket.assigns.current_user
    AI.reject_suggestion(suggestion, user.id)

    suggestions = AI.list_suggestions_for_ticket(socket.assigns.selected_ticket.id)
    {:noreply, assign(socket, :ai_suggestions, suggestions)}
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload_data(socket) do
    org_id = socket.assigns.org_id

    if org_id do
      filters = build_filters(socket.assigns)

      # Stat cards from DB (GROUP BY status) — one query for counts
      status_counts = Tickets.count_tickets_by_status(org_id, filters)
      counts = %{
        total: status_counts |> Map.values() |> Enum.sum(),
        open: Map.get(status_counts, "created", 0) + Map.get(status_counts, "triaged", 0),
        in_progress: Map.get(status_counts, "assigned", 0) + Map.get(status_counts, "in_progress", 0),
        on_hold: Map.get(status_counts, "on_hold", 0),
        completed: Map.get(status_counts, "completed", 0) + Map.get(status_counts, "reviewed", 0) + Map.get(status_counts, "closed", 0)
      }

      socket = assign(socket, :counts, counts)

      # Kanban always needs grouped data
      grouped = Tickets.list_tickets_by_status(org_id, filters, 20)
      socket = assign(socket, :grouped, grouped)

      case socket.assigns.view_mode do
        "kanban" ->
          # Kanban only uses grouped, no stream needed
          socket
          |> stream(:tickets, [], reset: true)
          |> assign(:cursor, nil)
          |> assign(:has_more, false)

        _ ->
          # List view: flat stream with cursor pagination
          page = Tickets.list_tickets_paginated(org_id, filters)
          socket
          |> assign(:cursor, page.cursor)
          |> assign(:has_more, page.has_more)
          |> stream(:tickets, page.entries, reset: true)
      end
    else
      empty_grouped =
        ~w(created triaged assigned in_progress on_hold pending_review completed reviewed closed)
        |> Enum.map(fn s -> {s, %{tickets: [], total: 0, has_more: false}} end)

      socket
      |> assign(:counts, %{total: 0, open: 0, in_progress: 0, on_hold: 0, completed: 0})
      |> assign(:grouped, empty_grouped)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> stream(:tickets, [], reset: true)
    end
  end

  defp reload_counts(socket) do
    if socket.assigns.org_id do
      filters = build_filters(socket.assigns)
      status_counts = Tickets.count_tickets_by_status(socket.assigns.org_id, filters)
      %{
        total: status_counts |> Map.values() |> Enum.sum(),
        open: Map.get(status_counts, "created", 0) + Map.get(status_counts, "triaged", 0),
        in_progress: Map.get(status_counts, "assigned", 0) + Map.get(status_counts, "in_progress", 0),
        on_hold: Map.get(status_counts, "on_hold", 0),
        completed: Map.get(status_counts, "completed", 0) + Map.get(status_counts, "reviewed", 0) + Map.get(status_counts, "closed", 0)
      }
    else
      %{total: 0, open: 0, in_progress: 0, on_hold: 0, completed: 0}
    end
  end

  defp maybe_reload_kanban(socket) do
    if socket.assigns.org_id do
      filters = build_filters(socket.assigns)
      grouped = Tickets.list_tickets_by_status(socket.assigns.org_id, filters, 20)
      assign(socket, :grouped, grouped)
    else
      socket
    end
  end

  defp build_filters(assigns) do
    filters = %{}
    filters = if MapSet.size(assigns.filter_statuses) > 0, do: Map.put(filters, :status, assigns.filter_statuses), else: filters
    filters = if MapSet.size(assigns.filter_priorities) > 0, do: Map.put(filters, :priority, assigns.filter_priorities), else: filters
    filters = if MapSet.size(assigns.filter_categories) > 0, do: Map.put(filters, :category, assigns.filter_categories), else: filters
    filters = if MapSet.size(assigns.filter_location_ids) > 0, do: Map.put(filters, :location_id, assigns.filter_location_ids), else: filters
    filters = if assigns.filter_date_from, do: Map.put(filters, :date_from, assigns.filter_date_from), else: filters
    filters = if assigns.filter_date_to, do: Map.put(filters, :date_to, assigns.filter_date_to), else: filters
    filters = if MapSet.size(assigns.filter_assignee_ids) > 0, do: Map.put(filters, :assignee_ids, assigns.filter_assignee_ids), else: filters
    filters = if assigns.search_query != "", do: Map.put(filters, :search, assigns.search_query), else: filters
    filters
  end

  defp matches_filters?(ticket, assigns) do
    (MapSet.size(assigns.filter_statuses) == 0 || MapSet.member?(assigns.filter_statuses, ticket.status)) &&
      (MapSet.size(assigns.filter_priorities) == 0 || MapSet.member?(assigns.filter_priorities, ticket.priority)) &&
      (MapSet.size(assigns.filter_categories) == 0 || MapSet.member?(assigns.filter_categories, ticket.category)) &&
      (MapSet.size(assigns.filter_location_ids) == 0 || MapSet.member?(assigns.filter_location_ids, ticket.location_id)) &&
      (MapSet.size(assigns.filter_assignee_ids) == 0 ||
        MapSet.member?(assigns.filter_assignee_ids, ticket.assigned_to_user_id) ||
        MapSet.member?(assigns.filter_assignee_ids, ticket.assigned_to_org_id))
  end

  defp status_actions("created"), do: [{"triaged", "Triage", "hero-clipboard-document-check"}, {"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("triaged"), do: [{"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("assigned"), do: [{"in_progress", "Start Work", "hero-play"}, {"on_hold", "Hold", "hero-pause"}]
  defp status_actions("in_progress"), do: [{"on_hold", "Hold", "hero-pause"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("on_hold"), do: [{"in_progress", "Resume", "hero-play"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("pending_review"), do: [{"completed", "Approve", "hero-check"}, {"in_progress", "Send Back", "hero-arrow-uturn-left"}]
  defp status_actions("completed"), do: [{"reviewed", "Review", "hero-eye"}, {"closed", "Close", "hero-x-circle"}]
  defp status_actions("reviewed"), do: [{"closed", "Close", "hero-x-circle"}]
  defp status_actions(_), do: []

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("pending_review"), do: "Pending Review"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(other)

  defp status_badge_class("created"), do: "badge-success badge-outline"
  defp status_badge_class("triaged"), do: "badge-info badge-outline"
  defp status_badge_class("assigned"), do: "badge-primary badge-outline"
  defp status_badge_class("in_progress"), do: "badge-info"
  defp status_badge_class("on_hold"), do: "badge-warning"
  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_dot_color("created"), do: "bg-success"
  defp status_dot_color("triaged"), do: "bg-info"
  defp status_dot_color("assigned"), do: "bg-primary"
  defp status_dot_color("in_progress"), do: "bg-info"
  defp status_dot_color("on_hold"), do: "bg-warning"
  defp status_dot_color("pending_review"), do: "bg-accent"
  defp status_dot_color("completed"), do: "bg-success"
  defp status_dot_color(_), do: "bg-base-content/30"

  defp priority_badge_class("emergency"), do: "badge-error"
  defp priority_badge_class("high"), do: "badge-warning"
  defp priority_badge_class("medium"), do: "bg-amber-100 text-amber-700 border-amber-200"
  defp priority_badge_class(_), do: "badge-ghost"

  defp priority_dot_class("emergency"), do: "bg-error-content"
  defp priority_dot_class("high"), do: "bg-warning-content"
  defp priority_dot_class("medium"), do: "bg-amber-500"
  defp priority_dot_class(_), do: "bg-base-content/40"

  defp sla_text(%{sla_deadline: nil}), do: "No deadline"
  defp sla_text(%{sla_paused_at: p}) when not is_nil(p), do: "Paused"
  defp sla_text(%{sla_deadline: deadline}) do
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
    cond do
      diff < 0 -> "#{abs(diff)} min overdue"
      diff < 60 -> "#{diff} min left"
      diff < 1440 -> "#{div(diff, 60)}h #{rem(diff, 60)}m left"
      true -> "#{div(diff, 1440)}d left"
    end
  end

  defp sla_color(%{sla_breached: true}), do: "text-error"
  defp sla_color(%{sla_deadline: nil}), do: "text-base-content/50"
  defp sla_color(%{sla_paused_at: p}) when not is_nil(p), do: "text-warning"
  defp sla_color(%{sla_deadline: deadline}) do
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
    cond do
      diff < 0 -> "text-error"
      diff < 120 -> "text-error"
      diff < 480 -> "text-warning"
      true -> "text-success"
    end
  end

  defp location_breadcrumb(location) do
    build_ancestor_names(location, []) |> Enum.join(" > ")
  end

  defp build_ancestor_names(nil, acc), do: acc
  defp build_ancestor_names(location, acc) do
    location = Fixly.Repo.preload(location, :parent)
    case location.parent do
      nil -> [location.name | acc]
      parent -> build_ancestor_names(parent, [location.name | acc])
    end
  end

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(_), do: "System"

  defp comment_initials(%{user: %{name: name}}) when is_binary(name) and name != "" do
    name |> String.split(" ") |> Enum.take(2) |> Enum.map(&String.first/1) |> Enum.join() |> String.upcase()
  end
  defp comment_initials(%{user: %{email: email}}) when is_binary(email), do: email |> String.first() |> String.upcase()
  defp comment_initials(_), do: "S"

  defp format_date(nil), do: ""
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d")

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."

  # --- Filter helpers ---

  defp active_filter_count(assigns) do
    count = 0
    count = if MapSet.size(assigns.filter_statuses) > 0, do: count + 1, else: count
    count = if MapSet.size(assigns.filter_priorities) > 0, do: count + 1, else: count
    count = if MapSet.size(assigns.filter_categories) > 0, do: count + 1, else: count
    count = if MapSet.size(assigns.filter_location_ids) > 0, do: count + 1, else: count
    count = if assigns.filter_date_from || assigns.filter_date_to, do: count + 1, else: count
    count + MapSet.size(assigns.filter_assignee_ids)
  end

  # --- Calendar helpers ---

  defp date_presets do
    [
      {"Today", "today"},
      {"Last 7 days", "7d"},
      {"Last 14 days", "14d"},
      {"Last 30 days", "30d"},
      {"Last 90 days", "90d"},
      {"Month to date", "mtd"},
      {"Year to date", "ytd"},
      {"All time", "all"}
    ]
  end

  defp calendar_days(month) do
    first = Date.new!(month.year, month.month, 1)
    # Monday = 1, Sunday = 7
    day_of_week = Date.day_of_week(first)
    # Start from the Monday before the first day
    start_date = Date.add(first, -(day_of_week - 1))
    # Generate 42 days (6 weeks)
    Enum.map(0..41, fn offset -> Date.add(start_date, offset) end)
  end

  defp in_selected_range?(_date, nil, _), do: false
  defp in_selected_range?(_date, _, nil), do: false
  defp in_selected_range?(date, from_str, to_str) do
    with {:ok, from} <- Date.from_iso8601(from_str),
         {:ok, to} <- Date.from_iso8601(to_str) do
      Date.compare(date, from) != :lt && Date.compare(date, to) != :gt
    else
      _ -> false
    end
  end

  defp is_range_endpoint?(_date, nil, nil), do: false
  defp is_range_endpoint?(date, from_str, to_str) do
    is_from = from_str && Date.to_iso8601(date) == from_str
    is_to = to_str && Date.to_iso8601(date) == to_str
    is_from || is_to
  end

  defp format_date_display(nil), do: "—"
  defp format_date_display(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
      _ -> date_str
    end
  end

  defp date_range_label(from, to) do
    parts = []
    parts = if from, do: parts ++ [format_date_display(from)], else: parts
    parts = if to, do: parts ++ [format_date_display(to)], else: parts
    Enum.join(parts, " — ")
  end

  defp filtered_assignees(all_assignees, query, selected_ids) do
    q = String.downcase(query)

    all_assignees
    |> Enum.reject(fn a -> MapSet.member?(selected_ids, a.id) end)
    |> Enum.filter(fn a -> String.contains?(String.downcase(a.name), q) end)
    |> Enum.take(8)
  end

  defp assignee_name(id, all_assignees) do
    case Enum.find(all_assignees, fn a -> a.id == id end) do
      nil -> "Unknown"
      a -> a.name
    end
  end

  # --- AI Suggestion helpers ---

  defp suggestion_type_label("category"), do: "Category"
  defp suggestion_type_label("priority"), do: "Priority"
  defp suggestion_type_label("create_asset"), do: "New Asset"
  defp suggestion_type_label("link_asset"), do: "Link Asset"
  defp suggestion_type_label(other), do: String.capitalize(other)

  defp suggestion_display_value(%{suggestion_type: "category", suggested_data: data}) do
    String.capitalize(data["category"] || "unknown")
  end

  defp suggestion_display_value(%{suggestion_type: "priority", suggested_data: data}) do
    String.capitalize(data["priority"] || "unknown")
  end

  defp suggestion_display_value(%{suggestion_type: "create_asset", suggested_data: data}) do
    name = data["name"] || "Unknown"
    cat = data["category"]
    if cat, do: "#{name} (#{cat})", else: name
  end

  defp suggestion_display_value(%{suggestion_type: "link_asset", suggested_data: data}) do
    data["asset_name"] || "Asset #{String.slice(data["asset_id"] || "", 0..7)}"
  end

  defp suggestion_display_value(_), do: "—"

  # --- Activity timeline helpers ---

  defp timeline_event_icon("status_change"), do: "hero-arrow-path"
  defp timeline_event_icon("assignment"), do: "hero-user-plus"
  defp timeline_event_icon("priority_change"), do: "hero-flag"
  defp timeline_event_icon("category_change"), do: "hero-tag"
  defp timeline_event_icon("asset_linked"), do: "hero-link"
  defp timeline_event_icon("sla_breach"), do: "hero-exclamation-triangle"
  defp timeline_event_icon("created"), do: "hero-plus-circle"
  defp timeline_event_icon("system"), do: "hero-cog-6-tooth"
  defp timeline_event_icon(_), do: "hero-information-circle"

  defp timeline_event_dot_bg("status_change"), do: "bg-info/10"
  defp timeline_event_dot_bg("assignment"), do: "bg-primary/10"
  defp timeline_event_dot_bg("priority_change"), do: "bg-warning/10"
  defp timeline_event_dot_bg("sla_breach"), do: "bg-error/10"
  defp timeline_event_dot_bg("asset_linked"), do: "bg-success/10"
  defp timeline_event_dot_bg("created"), do: "bg-success/10"
  defp timeline_event_dot_bg(_), do: "bg-base-200"

  defp timeline_event_icon_color("status_change"), do: "text-info"
  defp timeline_event_icon_color("assignment"), do: "text-primary"
  defp timeline_event_icon_color("priority_change"), do: "text-warning"
  defp timeline_event_icon_color("sla_breach"), do: "text-error"
  defp timeline_event_icon_color("asset_linked"), do: "text-success"
  defp timeline_event_icon_color("created"), do: "text-success"
  defp timeline_event_icon_color(_), do: "text-base-content/40"

  defp timeline_event_text(%{type: "status_change", metadata: %{"from" => from, "to" => to}}) do
    "Status changed from #{status_label(from)} to #{status_label(to)}"
  end

  defp timeline_event_text(%{type: "status_change", body: body}) do
    body
  end

  defp timeline_event_text(%{type: "assignment", metadata: %{"assigned_to" => name}}) do
    "Assigned to #{name}"
  end

  defp timeline_event_text(%{type: "assignment", body: body}) do
    body
  end

  defp timeline_event_text(%{type: "priority_change", metadata: %{"to" => to}}) do
    "Priority changed to #{String.capitalize(to)}"
  end

  defp timeline_event_text(%{type: "priority_change", body: body}) do
    body
  end

  defp timeline_event_text(%{type: "category_change", metadata: %{"to" => to}}) do
    "Category changed to #{String.capitalize(to)}"
  end

  defp timeline_event_text(%{type: "asset_linked", metadata: %{"asset_name" => name}}) do
    "Asset \"#{name}\" linked to this ticket"
  end

  defp timeline_event_text(%{type: "asset_linked", body: body}) do
    body
  end

  defp timeline_event_text(%{type: "sla_breach", metadata: %{"deadline" => deadline}}) do
    "SLA deadline breached (#{deadline})"
  end

  defp timeline_event_text(%{type: "sla_breach"}) do
    "SLA deadline breached"
  end

  defp timeline_event_text(%{type: "created", body: body}) do
    body
  end

  defp timeline_event_text(%{body: body}) do
    body
  end

  # --- Combobox filter helpers ---

  @ticket_statuses [{"created", "Open"}, {"triaged", "Triaged"}, {"assigned", "Assigned"}, {"in_progress", "In Progress"}, {"on_hold", "On Hold"}, {"completed", "Completed"}, {"reviewed", "Reviewed"}, {"closed", "Closed"}]
  @ticket_priorities [{"emergency", "Emergency"}, {"high", "High"}, {"medium", "Medium"}, {"low", "Low"}]

  defp filtered_ticket_statuses(""), do: @ticket_statuses
  defp filtered_ticket_statuses(q) do
    q = String.downcase(q)
    Enum.filter(@ticket_statuses, fn {_, label} -> String.contains?(String.downcase(label), q) end)
  end

  defp filtered_ticket_priorities(""), do: @ticket_priorities
  defp filtered_ticket_priorities(q) do
    q = String.downcase(q)
    Enum.filter(@ticket_priorities, fn {_, label} -> String.contains?(String.downcase(label), q) end)
  end

  defp filtered_ticket_categories(categories, ""), do: categories
  defp filtered_ticket_categories(categories, q) do
    q = String.downcase(q)
    Enum.filter(categories, fn cat -> String.contains?(String.downcase(cat), q) end)
  end

  defp filtered_ticket_locations(locations, ""), do: locations
  defp filtered_ticket_locations(locations, q) do
    q = String.downcase(q)
    Enum.filter(locations, fn loc -> String.contains?(String.downcase(loc.name), q) end)
  end

  defp priority_dot_color_filter("emergency"), do: "bg-red-500"
  defp priority_dot_color_filter("high"), do: "bg-orange-500"
  defp priority_dot_color_filter("medium"), do: "bg-yellow-500"
  defp priority_dot_color_filter("low"), do: "bg-blue-500"
  defp priority_dot_color_filter(_), do: "bg-gray-400"

  defp category_dot_color_filter("hvac"), do: "bg-red-500"
  defp category_dot_color_filter("plumbing"), do: "bg-blue-500"
  defp category_dot_color_filter("electrical"), do: "bg-yellow-500"
  defp category_dot_color_filter("structural"), do: "bg-stone-500"
  defp category_dot_color_filter("appliance"), do: "bg-purple-500"
  defp category_dot_color_filter("furniture"), do: "bg-emerald-500"
  defp category_dot_color_filter("it"), do: "bg-cyan-500"
  defp category_dot_color_filter(_), do: "bg-gray-400"

  defp maps_url(ticket) do
    cond do
      ticket.location && ticket.location.metadata["gps_lat"] && ticket.location.metadata["gps_lng"] ->
        lat = ticket.location.metadata["gps_lat"]
        lng = ticket.location.metadata["gps_lng"]
        "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}"

      ticket.location ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.location.name)}"

      ticket.custom_location_name ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.custom_location_name)}"

      true ->
        "#"
    end
  end
end
