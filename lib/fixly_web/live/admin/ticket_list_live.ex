defmodule FixlyWeb.Admin.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket
  alias Fixly.Accounts
  alias Fixly.Organizations
  alias Fixly.PubSubBroadcast

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    # Subscribe to real-time updates for this org
    if connected?(socket) && org_id do
      PubSubBroadcast.subscribe_org(org_id)
    end

    tickets = if org_id, do: Tickets.list_tickets(org_id), else: []
    grouped = group_by_status(tickets)
    counts = compute_counts(tickets)

    internal_users = if org_id, do: Accounts.list_users_by_organization(org_id), else: []
    contractor_orgs = if org_id, do: Organizations.list_contractor_orgs(org_id), else: []

    # Build the assignee list (all users + contractor orgs for the filter)
    all_assignees =
      Enum.map(internal_users, fn u -> %{id: u.id, name: u.name || u.email, type: "user"} end) ++
      Enum.map(contractor_orgs, fn o -> %{id: o.id, name: o.name, type: "org"} end)

    # Categories from existing tickets
    categories = tickets |> Enum.map(& &1.category) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

    # Locations from existing tickets
    locations = tickets |> Enum.map(& &1.location) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.name)

    socket =
      socket
      |> assign(:page_title, "Tickets")
      |> assign(:all_tickets, tickets)
      |> assign(:tickets, tickets)
      |> assign(:grouped, grouped)
      |> assign(:counts, counts)
      |> assign(:view_mode, "list")
      |> assign(:search_query, "")
      # Filters
      |> assign(:filter_status, "all")
      |> assign(:filter_priority, "all")
      |> assign(:filter_category, "all")
      |> assign(:filter_date_from, nil)
      |> assign(:filter_date_to, nil)
      |> assign(:filter_assignee_ids, MapSet.new())
      |> assign(:filter_location_id, "all")
      |> assign(:show_filters, false)
      |> assign(:assignee_search, "")
      # Reference data
      |> assign(:all_assignees, all_assignees)
      |> assign(:all_categories, categories)
      |> assign(:all_locations, locations)
      # Panel
      |> assign(:selected_ticket, nil)
      |> assign(:comments, [])
      |> assign(:comment_body, "")
      |> assign(:org_id, org_id)
      |> assign(:internal_users, internal_users)
      |> assign(:contractor_orgs, contractor_orgs)
      |> assign(:current_user, user)

    {:ok, socket}
  end

  # --- PubSub Handlers (real-time updates from other users/workers) ---

  @impl true
  def handle_info({:ticket_created, _ticket}, socket) do
    {:noreply, reload_tickets(socket)}
  end

  def handle_info({:ticket_updated, ticket}, socket) do
    socket = reload_tickets(socket)

    # If the updated ticket is the one we have open in the panel, refresh it
    socket =
      if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == ticket.id do
        updated = Tickets.get_ticket!(ticket.id)
        comments = Tickets.list_comments(ticket.id)
        assign(socket, selected_ticket: updated, comments: comments)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:sla_breached, _ticket}, socket) do
    {:noreply, reload_tickets(socket)}
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
            <.filter_chip :if={@filter_status != "all"} label={"Status: #{status_label(@filter_status)}"} event="clear_filter" value="status" />
            <.filter_chip :if={@filter_priority != "all"} label={"Priority: #{String.capitalize(@filter_priority)}"} event="clear_filter" value="priority" />
            <.filter_chip :if={@filter_category != "all"} label={"Category: #{String.capitalize(@filter_category)}"} event="clear_filter" value="category" />
            <.filter_chip :if={@filter_date_from} label={"From: #{@filter_date_from}"} event="clear_filter" value="date_from" />
            <.filter_chip :if={@filter_date_to} label={"To: #{@filter_date_to}"} event="clear_filter" value="date_to" />
            <.filter_chip :if={@filter_location_id != "all"} label={"Location"} event="clear_filter" value="location" />
            <.filter_chip
              :for={aid <- MapSet.to_list(@filter_assignee_ids)}
              label={assignee_name(aid, @all_assignees)}
              event="remove_assignee"
              value={aid}
            />
          </div>

          <!-- Filter panel (collapsible) -->
          <div :if={@show_filters} class="px-5 py-4 border-b border-base-300 bg-base-200/20">
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
              <!-- Status -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Status</label>
                <form phx-change="set_filter_status">
                  <select name="status" class="select select-sm select-bordered w-full" value={@filter_status}>
                    <option :for={{val, label} <- [{"all", "All Statuses"}, {"created", "Open"}, {"triaged", "Triaged"}, {"assigned", "Assigned"}, {"on_hold", "On Hold"}, {"in_progress", "In Progress"}, {"completed", "Completed"}, {"closed", "Closed"}]} value={val} selected={@filter_status == val}>
                      {label}
                    </option>
                  </select>
                </form>
              </div>

              <!-- Priority -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Priority</label>
                <form phx-change="set_filter_priority">
                  <select name="priority" class="select select-sm select-bordered w-full">
                    <option :for={{val, label} <- [{"all", "All Priorities"}, {"emergency", "Emergency"}, {"high", "High"}, {"medium", "Medium"}, {"low", "Low"}]} value={val} selected={@filter_priority == val}>
                      {label}
                    </option>
                  </select>
                </form>
              </div>

              <!-- Category -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Category</label>
                <form phx-change="set_filter_category">
                  <select name="category" class="select select-sm select-bordered w-full">
                    <option value="all" selected={@filter_category == "all"}>All Categories</option>
                    <option :for={cat <- @all_categories} value={cat} selected={@filter_category == cat}>
                      {String.capitalize(cat)}
                    </option>
                  </select>
                </form>
              </div>

              <!-- Location -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Location</label>
                <form phx-change="set_filter_location">
                  <select name="location_id" class="select select-sm select-bordered w-full">
                    <option value="all" selected={@filter_location_id == "all"}>All Locations</option>
                    <option :for={loc <- @all_locations} value={loc.id} selected={@filter_location_id == loc.id}>
                      {loc.name}
                    </option>
                  </select>
                </form>
              </div>

              <!-- Date from -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Date From</label>
                <form phx-change="set_filter_date_from">
                  <input
                    type="date"
                    name="date"
                    value={@filter_date_from}
                    class="input input-sm input-bordered w-full"
                  />
                </form>
              </div>

              <!-- Date to -->
              <div>
                <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-1.5 block">Date To</label>
                <form phx-change="set_filter_date_to">
                  <input
                    type="date"
                    name="date"
                    value={@filter_date_to}
                    class="input input-sm input-bordered w-full"
                  />
                </form>
              </div>

              <!-- Assigned To (multi-select combobox) -->
              <div class="col-span-2">
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

          <!-- List view -->
          <div :if={@view_mode == "list"}>
            <%= if @tickets == [] do %>
              <.empty_state />
            <% else %>
              <.ticket_table_grouped grouped={@grouped} selected_id={@selected_ticket && @selected_ticket.id} />
            <% end %>
          </div>

          <!-- Kanban view -->
          <div :if={@view_mode == "kanban"} class="p-5 flex-1">
            <%= if @tickets == [] do %>
              <.empty_state />
            <% else %>
              <.kanban_board grouped={@grouped} selected_id={@selected_ticket && @selected_ticket.id} />
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
            <div class="flex items-center gap-1.5 text-sm text-base-content">
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
            <div class="flex items-center gap-2">
              <div class="w-6 h-6 rounded-full bg-base-200 flex items-center justify-center">
                <span class="text-[10px] font-semibold text-base-content/60">
                  {String.first(@ticket.submitter_name) |> String.upcase()}
                </span>
              </div>
              <span class="text-sm text-base-content">{@ticket.submitter_name}</span>
            </div>
          </.info_row>

          <.info_row :if={@ticket.assigned_to_user} label="Assigned to">
            <div class="flex items-center gap-2">
              <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center">
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
        <a
          :if={@ticket.location}
          href={"https://www.google.com/maps/search/?api=1&query=#{URI.encode(@ticket.location.name)}"}
          target="_blank"
          class="btn btn-sm btn-outline w-full gap-2"
        >
          <.icon name="hero-map-pin" class="size-4" />
          Navigate to Location
        </a>

        <!-- Comments / Discussion -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider">
              Discussion
              <span :if={@comments != []} class="ml-1 badge badge-xs badge-ghost">{length(@comments)}</span>
            </p>
          </div>

          <div class="space-y-3 mb-3 max-h-64 overflow-y-auto">
            <div :for={comment <- @comments} class="flex gap-2.5">
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
                <p class="text-sm text-base-content/70 leading-relaxed">{comment.body}</p>
              </div>
            </div>
            <p :if={@comments == []} class="text-xs text-base-content/40 text-center py-3">No comments yet</p>
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
  # GROUPED TABLE
  # ==========================================

  attr :grouped, :list, required: true
  attr :selected_id, :string, default: nil

  defp ticket_table_grouped(assigns) do
    ~H"""
    <div>
      <.ticket_group
        :for={{status, tickets} <- @grouped}
        :if={tickets != []}
        status={status}
        tickets={tickets}
        selected_id={@selected_id}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :selected_id, :string, default: nil

  defp ticket_group(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 px-5 py-2.5 bg-base-200/50 border-b border-base-300">
        <div class={["w-1 h-4 rounded-full", status_bar_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">{status_label(@status)}</span>
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
      </div>
      <div class="grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
        <span>Ticket</span><span>Location</span><span>Category</span><span>Priority</span><span>Assigned To</span><span>Date</span>
      </div>
      <.ticket_row :for={ticket <- @tickets} ticket={ticket} selected={@selected_id == ticket.id} />
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :selected, :boolean, default: false

  defp ticket_row(assigns) do
    ~H"""
    <div
      phx-click="select_ticket"
      phx-value-id={@ticket.id}
      class={[
        "grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center cursor-pointer transition-colors",
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
  attr :selected_id, :string, default: nil

  defp kanban_board(assigns) do
    ~H"""
    <div class="flex gap-4 overflow-x-auto pb-4 items-stretch min-h-[400px]">
      <.kanban_column :for={{status, tickets} <- @grouped} status={status} tickets={tickets} selected_id={@selected_id} />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :selected_id, :string, default: nil

  defp kanban_column(assigns) do
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
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
      </div>
      <div class="space-y-2.5 flex-1 min-h-[200px] kanban-dropzone rounded-lg transition-colors p-1">
        <.kanban_card :for={ticket <- @tickets} ticket={ticket} selected={@selected_id == ticket.id} />
      </div>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
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
        <div class="flex flex-wrap gap-1.5">
          <.priority_badge :if={@ticket.priority} priority={@ticket.priority} />
          <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
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
      {:noreply, assign(socket, selected_ticket: nil, comments: [])}
    else
      ticket = Tickets.get_ticket!(id)
      require Logger
      Logger.info("SELECT_TICKET #{ticket.reference_number}: org=#{inspect(ticket.assigned_to_org_id)}, user=#{inspect(ticket.assigned_to_user_id)}")
      comments = Tickets.list_comments(id)
      {:noreply, assign(socket, selected_ticket: ticket, comments: comments, comment_body: "")}
    end
  end

  def handle_event("close_panel", _, socket) do
    {:noreply, assign(socket, selected_ticket: nil, comments: [])}
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    filtered = filter_tickets_by_search(socket.assigns.tickets, query)

    {:noreply,
     socket
     |> assign(search_query: query, grouped: group_by_status(filtered))}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply,
     socket
     |> assign(search_query: "", grouped: group_by_status(socket.assigns.tickets))}
  end

  # --- Kanban Drag & Drop ---

  def handle_event("kanban_drop", %{"ticket_id" => ticket_id, "new_status" => new_status}, socket) do
    ticket = Tickets.get_ticket!(ticket_id)

    # Handle SLA pause/resume on status change
    case new_status do
      "on_hold" -> Tickets.pause_sla(ticket)
      "in_progress" when ticket.status == "on_hold" -> Tickets.resume_sla(ticket)
      _ -> :ok
    end

    {:ok, _} = Tickets.update_ticket(ticket, %{status: new_status})
    Tickets.log_activity(ticket.id, "status_change", "Status changed to #{status_label(new_status)}", %{from: ticket.status, to: new_status})

    updated = Tickets.get_ticket!(ticket.id)
    PubSubBroadcast.broadcast_ticket_updated(updated)

    # Refresh selected ticket if it's the one we moved
    socket =
      if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == ticket_id do
        assign(socket, :selected_ticket, updated)
      else
        socket
      end

    {:noreply, reload_tickets(socket)}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  def handle_event("toggle_filters", _, socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  def handle_event("set_filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter_status, status) |> apply_all_filters()}
  end

  def handle_event("set_filter_priority", %{"priority" => priority}, socket) do
    {:noreply, socket |> assign(:filter_priority, priority) |> apply_all_filters()}
  end

  def handle_event("set_filter_category", %{"category" => category}, socket) do
    {:noreply, socket |> assign(:filter_category, category) |> apply_all_filters()}
  end

  def handle_event("set_filter_location", %{"location_id" => location_id}, socket) do
    {:noreply, socket |> assign(:filter_location_id, location_id) |> apply_all_filters()}
  end

  def handle_event("set_filter_date_from", %{"date" => ""}, socket) do
    {:noreply, socket |> assign(:filter_date_from, nil) |> apply_all_filters()}
  end

  def handle_event("set_filter_date_from", %{"date" => date}, socket) do
    {:noreply, socket |> assign(:filter_date_from, date) |> apply_all_filters()}
  end

  def handle_event("set_filter_date_to", %{"date" => ""}, socket) do
    {:noreply, socket |> assign(:filter_date_to, nil) |> apply_all_filters()}
  end

  def handle_event("set_filter_date_to", %{"date" => date}, socket) do
    {:noreply, socket |> assign(:filter_date_to, date) |> apply_all_filters()}
  end

  def handle_event("assignee_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :assignee_search, query)}
  end

  def handle_event("add_assignee", %{"id" => id}, socket) do
    ids = MapSet.put(socket.assigns.filter_assignee_ids, id)
    {:noreply, socket |> assign(filter_assignee_ids: ids, assignee_search: "") |> apply_all_filters()}
  end

  def handle_event("remove_assignee", %{"id" => id}, socket) do
    ids = MapSet.delete(socket.assigns.filter_assignee_ids, id)
    {:noreply, socket |> assign(:filter_assignee_ids, ids) |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "status"}, socket) do
    {:noreply, socket |> assign(:filter_status, "all") |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "priority"}, socket) do
    {:noreply, socket |> assign(:filter_priority, "all") |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "category"}, socket) do
    {:noreply, socket |> assign(:filter_category, "all") |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "location"}, socket) do
    {:noreply, socket |> assign(:filter_location_id, "all") |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "date_from"}, socket) do
    {:noreply, socket |> assign(:filter_date_from, nil) |> apply_all_filters()}
  end

  def handle_event("clear_filter", %{"id" => "date_to"}, socket) do
    {:noreply, socket |> assign(:filter_date_to, nil) |> apply_all_filters()}
  end

  def handle_event("clear_all_filters", _, socket) do
    {:noreply,
     socket
     |> assign(
       filter_status: "all",
       filter_priority: "all",
       filter_category: "all",
       filter_date_from: nil,
       filter_date_to: nil,
       filter_assignee_ids: MapSet.new(),
       filter_location_id: "all",
       assignee_search: "",
       search_query: ""
     )
     |> apply_all_filters()}
  end

  def handle_event("set_priority", %{"priority" => priority}, socket) do
    {:ok, ticket} = Tickets.set_priority(socket.assigns.selected_ticket, priority)
    ticket = Tickets.get_ticket!(ticket.id)
    Tickets.log_activity(ticket.id, "system", "Priority set to #{priority}")
    PubSubBroadcast.broadcast_ticket_updated(ticket)
    {:noreply, socket |> assign(selected_ticket: ticket) |> reload_tickets()}
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    ticket = socket.assigns.selected_ticket

    case status do
      "on_hold" -> Tickets.pause_sla(ticket)
      "in_progress" when ticket.status == "on_hold" -> Tickets.resume_sla(ticket)
      _ -> :ok
    end

    {:ok, _} = Tickets.update_ticket(ticket, %{status: status})
    Tickets.log_activity(ticket.id, "status_change", "Status changed to #{status_label(status)}", %{from: ticket.status, to: status})
    updated = Tickets.get_ticket!(ticket.id)
    PubSubBroadcast.broadcast_ticket_updated(updated)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("assign_to_org", params, socket) do
    require Logger
    org_id = params["org_id"]
    ticket = socket.assigns.selected_ticket
    current_org_id = ticket.assigned_to_org_id || ""
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
        Tickets.log_activity(ticket.id, "assignment", "Assigned to contractor")
      end

      updated = Tickets.get_ticket!(ticket.id)
      PubSubBroadcast.broadcast_ticket_updated(updated)
      {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
    end
  end

  def handle_event("assign_to_user", params, socket) do
    user_id = params["user_id"]
    ticket = socket.assigns.selected_ticket
    current_user_id = ticket.assigned_to_user_id || ""

    # Skip if nothing changed (prevents re-render loops)
    if user_id == current_user_id do
      {:noreply, socket}
    else
      if user_id == "" || is_nil(user_id) do
        {:ok, _} = Tickets.update_ticket(ticket, %{assigned_to_user_id: nil})
      else
        {:ok, _} = Tickets.assign_ticket(ticket, %{assigned_to_user_id: user_id})
        Tickets.log_activity(ticket.id, "assignment", "Assigned to technician")
      end

      updated = Tickets.get_ticket!(ticket.id)
      PubSubBroadcast.broadcast_ticket_updated(updated)
      {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
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

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload_tickets(socket) do
    tickets = if socket.assigns.org_id, do: Tickets.list_tickets(socket.assigns.org_id), else: []
    socket
    |> assign(all_tickets: tickets, tickets: tickets)
    |> assign(counts: compute_counts(tickets))
    |> apply_all_filters()
  end

  defp apply_all_filters(socket) do
    filtered =
      socket.assigns.all_tickets
      |> filter_by_status(socket.assigns.filter_status)
      |> filter_by_priority(socket.assigns.filter_priority)
      |> filter_by_category(socket.assigns.filter_category)
      |> filter_by_location(socket.assigns.filter_location_id)
      |> filter_by_date_from(socket.assigns.filter_date_from)
      |> filter_by_date_to(socket.assigns.filter_date_to)
      |> filter_by_assignees(socket.assigns.filter_assignee_ids)
      |> filter_tickets_by_search(socket.assigns.search_query)

    assign(socket, tickets: filtered, grouped: group_by_status(filtered))
  end

  defp filter_by_status(tickets, "all"), do: tickets
  defp filter_by_status(tickets, status), do: Enum.filter(tickets, &(&1.status == status))

  defp filter_by_priority(tickets, "all"), do: tickets
  defp filter_by_priority(tickets, priority), do: Enum.filter(tickets, &(&1.priority == priority))

  defp filter_by_category(tickets, "all"), do: tickets
  defp filter_by_category(tickets, category), do: Enum.filter(tickets, &(&1.category == category))

  defp filter_by_location(tickets, "all"), do: tickets
  defp filter_by_location(tickets, location_id), do: Enum.filter(tickets, &(&1.location_id == location_id))

  defp filter_by_date_from(tickets, nil), do: tickets
  defp filter_by_date_from(tickets, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        from = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        Enum.filter(tickets, &(DateTime.compare(&1.inserted_at, from) != :lt))
      _ -> tickets
    end
  end

  defp filter_by_date_to(tickets, nil), do: tickets
  defp filter_by_date_to(tickets, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        to = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        Enum.filter(tickets, &(DateTime.compare(&1.inserted_at, to) != :gt))
      _ -> tickets
    end
  end

  defp filter_by_assignees(tickets, assignee_ids) do
    if MapSet.size(assignee_ids) == 0 do
      tickets
    else
      Enum.filter(tickets, fn t ->
        MapSet.member?(assignee_ids, t.assigned_to_user_id) ||
          MapSet.member?(assignee_ids, t.assigned_to_org_id)
      end)
    end
  end

  defp compute_counts(tickets) do
    %{
      total: length(tickets),
      open: length(Enum.filter(tickets, &(&1.status in ["created", "triaged"]))),
      in_progress: length(Enum.filter(tickets, &(&1.status in ["assigned", "in_progress"]))),
      on_hold: length(Enum.filter(tickets, &(&1.status == "on_hold"))),
      completed: length(Enum.filter(tickets, &(&1.status in ["completed", "reviewed", "closed"])))
    }
  end

  @status_order ["created", "triaged", "assigned", "on_hold", "in_progress", "completed", "reviewed", "closed"]

  defp group_by_status(tickets) do
    grouped = Enum.group_by(tickets, & &1.status)
    Enum.map(@status_order, fn s -> {s, Map.get(grouped, s, [])} end)
  end

  defp filter_tickets_by_search(tickets, ""), do: tickets
  defp filter_tickets_by_search(tickets, query) do
    q = String.downcase(query)

    Enum.filter(tickets, fn t ->
      String.contains?(String.downcase(t.description || ""), q) ||
        String.contains?(String.downcase(t.reference_number || ""), q) ||
        String.contains?(String.downcase(t.submitter_name || ""), q) ||
        String.contains?(String.downcase(t.category || ""), q) ||
        String.contains?(String.downcase(t.custom_item_name || ""), q) ||
        (t.location && String.contains?(String.downcase(t.location.name || ""), q))
    end)
  end

  defp status_actions("created"), do: [{"triaged", "Triage", "hero-clipboard-document-check"}, {"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("triaged"), do: [{"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("assigned"), do: [{"in_progress", "Start Work", "hero-play"}, {"on_hold", "Hold", "hero-pause"}]
  defp status_actions("in_progress"), do: [{"on_hold", "Hold", "hero-pause"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("on_hold"), do: [{"in_progress", "Resume", "hero-play"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("completed"), do: [{"reviewed", "Review", "hero-eye"}, {"closed", "Close", "hero-x-circle"}]
  defp status_actions("reviewed"), do: [{"closed", "Close", "hero-x-circle"}]
  defp status_actions(_), do: []

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
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

  defp status_bar_color("created"), do: "bg-success"
  defp status_bar_color("triaged"), do: "bg-info"
  defp status_bar_color("assigned"), do: "bg-primary"
  defp status_bar_color("in_progress"), do: "bg-info"
  defp status_bar_color("on_hold"), do: "bg-warning"
  defp status_bar_color("completed"), do: "bg-success"
  defp status_bar_color(_), do: "bg-base-content/30"

  defp status_dot_color("created"), do: "bg-success"
  defp status_dot_color("triaged"), do: "bg-info"
  defp status_dot_color("assigned"), do: "bg-primary"
  defp status_dot_color("in_progress"), do: "bg-info"
  defp status_dot_color("on_hold"), do: "bg-warning"
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
    count = if assigns.filter_status != "all", do: count + 1, else: count
    count = if assigns.filter_priority != "all", do: count + 1, else: count
    count = if assigns.filter_category != "all", do: count + 1, else: count
    count = if assigns.filter_location_id != "all", do: count + 1, else: count
    count = if assigns.filter_date_from, do: count + 1, else: count
    count = if assigns.filter_date_to, do: count + 1, else: count
    count + MapSet.size(assigns.filter_assignee_ids)
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
end
