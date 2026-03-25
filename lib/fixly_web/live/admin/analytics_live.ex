defmodule FixlyWeb.Admin.AnalyticsLive do
  use FixlyWeb, :live_view

  import Ecto.Query

  alias Fixly.Analytics.Engine
  alias Fixly.Locations
  alias Fixly.Tickets.Ticket

  @categories Ticket.categories()
  @priorities Ticket.priorities()

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    tree = if org_id, do: Locations.get_tree(org_id), else: []

    socket =
      socket
      |> assign(:page_title, "Analytics")
      |> assign(:org_id, org_id)
      |> assign(:tree, tree)
      |> assign(:selected_location_ids, MapSet.new())
      |> assign(:expanded_locations, MapSet.new())
      |> assign(:filter_categories, MapSet.new())
      |> assign(:filter_priorities, MapSet.new())
      |> assign(:filter_from, "")
      |> assign(:filter_to, "")
      |> assign(:categories, @categories)
      |> assign(:priorities, @priorities)
      |> assign(:show_date_picker, false)
      |> assign(:calendar_month, Date.utc_today())
      |> assign(:show_category_filter, false)
      |> assign(:category_filter_search, "")
      |> assign(:show_priority_filter, false)
      |> assign(:priority_filter_search, "")
      |> run_analytics()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div>
        <h1 class="text-2xl font-bold text-base-content">Analytics</h1>
        <p class="text-sm text-base-content/50 mt-1">Cross-selection analysis of your ticket data</p>
      </div>

      <div class="flex gap-6">
        <!-- Left Panel: Location Tree -->
        <div class="w-72 shrink-0 hidden lg:block">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm sticky top-6">
            <div class="px-4 py-3 border-b border-base-300 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-base-content">Locations</h2>
              <button
                :if={MapSet.size(@selected_location_ids) > 0}
                phx-click="clear_locations"
                class="text-xs text-primary hover:underline"
              >
                Clear all
              </button>
            </div>
            <div class="p-3 max-h-[60vh] overflow-y-auto">
              <%= if @tree == [] do %>
                <p class="text-sm text-base-content/40 text-center py-4">No locations</p>
              <% else %>
                <div class="space-y-0.5">
                  <.location_checkbox
                    :for={node <- @tree}
                    node={node}
                    selected={@selected_location_ids}
                    expanded={@expanded_locations}
                    depth={0}
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Main Panel -->
        <div class="flex-1 min-w-0 space-y-6">
          <!-- Filter Bar -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
            <div class="flex flex-wrap items-center gap-3">
              <!-- Category Combobox -->
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
                      :for={cat <- filtered_analytics_categories(@categories, @category_filter_search)}
                      phx-click="toggle_category_item"
                      phx-value-id={cat}
                      class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_categories, cat) && "bg-primary border-primary", !MapSet.member?(@filter_categories, cat) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_categories, cat)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class={["w-2.5 h-2.5 rounded-full shrink-0", category_dot_color(cat)]}></span>
                      <span class="text-sm">{String.capitalize(cat)}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_category_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_category_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <!-- Priority Combobox -->
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
                      :for={pri <- filtered_analytics_priorities(@priorities, @priority_filter_search)}
                      phx-click="toggle_priority_item"
                      phx-value-id={pri}
                      class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                    >
                      <div class={["w-4 h-4 rounded border flex items-center justify-center shrink-0", MapSet.member?(@filter_priorities, pri) && "bg-primary border-primary", !MapSet.member?(@filter_priorities, pri) && "border-base-300"]}>
                        <.icon :if={MapSet.member?(@filter_priorities, pri)} name="hero-check" class="size-2.5 text-primary-content" />
                      </div>
                      <span class={["w-2.5 h-2.5 rounded-full shrink-0", priority_dot_color(pri)]}></span>
                      <span class="text-sm">{String.capitalize(pri)}</span>
                    </button>
                  </div>
                  <div class="p-2 border-t border-base-200 flex justify-between">
                    <button phx-click="clear_priority_filter" class="btn btn-xs btn-ghost">Clear</button>
                    <button phx-click="toggle_priority_filter" class="btn btn-xs btn-primary">Done</button>
                  </div>
                </div>
              </div>

              <!-- Date Range Picker -->
              <div class="relative">
                <button type="button" phx-click="toggle_date_picker" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[180px] justify-between font-normal">
                  <div class="flex items-center gap-1.5">
                    <.icon name="hero-calendar-days" class="size-4 text-base-content/40" />
                    <span :if={@filter_from == "" && @filter_to == ""} class="text-base-content/60">Date Range</span>
                    <span :if={@filter_from != "" || @filter_to != ""} class="text-base-content text-xs">
                      {format_date_display(@filter_from)} — {format_date_display(@filter_to)}
                    </span>
                  </div>
                  <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                </button>

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
                      <div class="flex items-center justify-between mb-3">
                        <button phx-click="calendar_prev_month" class="btn btn-ghost btn-xs btn-square">
                          <.icon name="hero-chevron-left" class="size-4" />
                        </button>
                        <span class="text-sm font-semibold text-base-content">{Calendar.strftime(@calendar_month, "%B %Y")}</span>
                        <button phx-click="calendar_next_month" class="btn btn-ghost btn-xs btn-square">
                          <.icon name="hero-chevron-right" class="size-4" />
                        </button>
                      </div>
                      <div class="grid grid-cols-7 gap-0 mb-1">
                        <span :for={day <- ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]} class="text-center text-[10px] font-semibold text-base-content/40 py-1">{day}</span>
                      </div>
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
                            in_selected_range?(date, @filter_from, @filter_to) && "bg-primary/10",
                            is_range_endpoint?(date, @filter_from, @filter_to) && "!bg-primary !text-primary-content font-semibold"
                          ]}
                        >
                          {date.day}
                        </button>
                      </div>
                    </div>
                  </div>
                  <div class="flex items-center justify-between px-4 py-2.5 border-t border-base-300 bg-base-200/30 rounded-b-xl">
                    <div class="text-xs text-base-content/50">
                      <span :if={@filter_from != ""}>{@filter_from}</span>
                      <span :if={@filter_from != "" && @filter_to != ""}> — {@filter_to}</span>
                      <span :if={@filter_from != "" && @filter_to == ""} class="text-primary animate-pulse"> pick end date</span>
                    </div>
                    <div class="flex gap-1.5">
                      <button phx-click="clear_date_range" class="btn btn-xs btn-ghost">Clear</button>
                      <button phx-click="toggle_date_picker" class="btn btn-xs btn-primary">Done</button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Active filter chips (mobile: show selected locations) -->
              <div :if={MapSet.size(@selected_location_ids) > 0} class="flex items-center gap-1 lg:hidden">
                <span class="badge badge-primary badge-sm gap-1">
                  <.icon name="hero-map-pin" class="size-3" />
                  {MapSet.size(@selected_location_ids)} locations
                  <button type="button" phx-click="clear_locations" class="ml-0.5">
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </span>
              </div>
            </div>
          </div>

          <!-- Stats Summary -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <.analytics_stat label="Total Tickets" value={@stats.total} icon="hero-ticket" color="blue" />
            <.analytics_stat label="SLA Compliance" value={"#{@stats.sla_compliance}%"} icon="hero-shield-check" color={if @stats.sla_compliance >= 90, do: "emerald", else: "red"} />
            <.analytics_stat label="Avg Resolution" value={if @stats.avg_resolution_hours, do: "#{@stats.avg_resolution_hours}h", else: "--"} icon="hero-clock" color="sky" />
            <.analytics_stat label="SLA Breaches" value={@stats.sla_breached} icon="hero-exclamation-triangle" color={if @stats.sla_breached == 0, do: "emerald", else: "red"} />
          </div>

          <!-- Category Breakdown -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Category Breakdown</h2>
            </div>
            <div class="p-5">
              <%= if @stats.by_category == %{} do %>
                <p class="text-sm text-base-content/40 text-center py-4">No data for current filters</p>
              <% else %>
                <div class="space-y-3">
                  <%= for {category, count} <- Enum.sort_by(@stats.by_category, fn {_k, v} -> -v end) do %>
                    <% max_val = @stats.by_category |> Map.values() |> Enum.max(fn -> 1 end) %>
                    <% pct = if max_val > 0, do: count / max_val * 100, else: 0 %>
                    <div class="flex items-center gap-3">
                      <span class="text-sm text-base-content capitalize w-24 shrink-0">{category}</span>
                      <div class="flex-1 h-6 bg-base-200 rounded overflow-hidden">
                        <div
                          class={"h-full rounded flex items-center px-2 #{category_color(category)}"}
                          style={"width: #{max(pct, 4)}%"}
                        >
                          <span class="text-[10px] font-bold text-white">{count}</span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Location Breakdown Table -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Location Breakdown</h2>
            </div>
            <%= if @location_breakdown == [] do %>
              <div class="p-5 text-center py-8">
                <p class="text-sm text-base-content/40">
                  <%= if MapSet.size(@selected_location_ids) == 0 do %>
                    Select locations from the left panel to see breakdown
                  <% else %>
                    No ticket data for selected locations
                  <% end %>
                </p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr class="text-base-content/50">
                      <th>Location</th>
                      <th class="text-right">Total</th>
                      <th class="text-right">Open</th>
                      <th class="text-right">Closed</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for row <- @location_breakdown do %>
                      <tr class="hover:bg-base-200/30">
                        <td class="font-medium text-base-content">{row.location_name}</td>
                        <td class="text-right text-base-content/70">{row.ticket_count}</td>
                        <td class="text-right text-base-content/70">{row.open}</td>
                        <td class="text-right text-base-content/70">{row.closed}</td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>

          <!-- Contractor Performance -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Contractor Performance</h2>
            </div>
            <%= if @contractor_perf == [] do %>
              <div class="p-5 text-center py-8">
                <p class="text-sm text-base-content/40">No contractor data for current filters</p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr class="text-base-content/50">
                      <th>Contractor</th>
                      <th class="text-right">Assigned</th>
                      <th class="text-right">Completed</th>
                      <th class="text-right">Breached</th>
                      <th class="text-right">SLA %</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for cp <- @contractor_perf do %>
                      <% sla_pct = if cp.total > 0, do: Float.round((cp.total - cp.breached) / cp.total * 100, 1), else: 100.0 %>
                      <tr class="hover:bg-base-200/30">
                        <td class="font-medium text-base-content">{cp.org_name}</td>
                        <td class="text-right text-base-content/70">{cp.total}</td>
                        <td class="text-right text-base-content/70">{cp.completed}</td>
                        <td class="text-right">
                          <span class={if cp.breached > 0, do: "text-error font-medium", else: "text-base-content/70"}>
                            {cp.breached}
                          </span>
                        </td>
                        <td class="text-right">
                          <span class={[
                            "font-semibold",
                            sla_pct >= 90 && "text-success",
                            sla_pct >= 70 && sla_pct < 90 && "text-warning",
                            sla_pct < 70 && "text-error"
                          ]}>
                            {sla_pct}%
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # COMPONENTS
  # ==========================================

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, default: nil
  attr :color, :string, default: "blue"

  defp analytics_stat(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
      <div class="flex items-center justify-between mb-3">
        <div :if={@icon} class={["w-9 h-9 rounded-lg flex items-center justify-center", stat_bg(@color)]}>
          <.icon name={@icon} class={"size-4 #{stat_icon_color(@color)}"} />
        </div>
      </div>
      <p class="text-2xl font-bold text-base-content">{@value}</p>
      <p class="text-xs font-medium text-base-content/50 mt-1">{@label}</p>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :selected, :any, required: true
  attr :expanded, :any, required: true
  attr :depth, :integer, default: 0

  defp location_checkbox(assigns) do
    has_children = assigns.node.children != []
    is_expanded = MapSet.member?(assigns.expanded, assigns.node.id)
    is_selected = MapSet.member?(assigns.selected, assigns.node.id)
    assigns = assign(assigns, has_children: has_children, is_expanded: is_expanded, is_selected: is_selected)

    ~H"""
    <div>
      <div
        class="flex items-center gap-1.5 py-1 rounded hover:bg-base-200/50 transition-colors"
        style={"padding-left: #{@depth * 16 + 4}px"}
      >
        <!-- Expand toggle -->
        <button
          :if={@has_children}
          phx-click="toggle_loc_expand"
          phx-value-id={@node.id}
          class="w-4 h-4 flex items-center justify-center shrink-0"
        >
          <.icon
            name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="size-3 text-base-content/40"
          />
        </button>
        <div :if={!@has_children} class="w-4 shrink-0"></div>

        <!-- Checkbox -->
        <input
          type="checkbox"
          class="checkbox checkbox-xs checkbox-primary"
          checked={@is_selected}
          phx-click="toggle_location"
          phx-value-id={@node.id}
        />

        <!-- Label -->
        <span class="text-xs text-base-content truncate">{@node.name}</span>
      </div>

      <!-- Children -->
      <div :if={@is_expanded && @has_children}>
        <.location_checkbox
          :for={child <- @node.children}
          node={child}
          selected={@selected}
          expanded={@expanded}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true

  # --- Category combobox ---

  def handle_event("toggle_category_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_category_filter, !socket.assigns.show_category_filter)
     |> assign(:show_priority_filter, false)}
  end

  def handle_event("close_category_filter", _, socket) do
    {:noreply, assign(socket, :show_category_filter, false)}
  end

  def handle_event("search_category_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :category_filter_search, query)}
  end

  def handle_event("toggle_category_item", %{"id" => cat}, socket) do
    updated =
      if MapSet.member?(socket.assigns.filter_categories, cat),
        do: MapSet.delete(socket.assigns.filter_categories, cat),
        else: MapSet.put(socket.assigns.filter_categories, cat)

    {:noreply, socket |> assign(:filter_categories, updated) |> run_analytics()}
  end

  def handle_event("clear_category_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:filter_categories, MapSet.new())
     |> assign(:category_filter_search, "")
     |> run_analytics()}
  end

  # --- Priority combobox ---

  def handle_event("toggle_priority_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_priority_filter, !socket.assigns.show_priority_filter)
     |> assign(:show_category_filter, false)}
  end

  def handle_event("close_priority_filter", _, socket) do
    {:noreply, assign(socket, :show_priority_filter, false)}
  end

  def handle_event("search_priority_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :priority_filter_search, query)}
  end

  def handle_event("toggle_priority_item", %{"id" => pri}, socket) do
    updated =
      if MapSet.member?(socket.assigns.filter_priorities, pri),
        do: MapSet.delete(socket.assigns.filter_priorities, pri),
        else: MapSet.put(socket.assigns.filter_priorities, pri)

    {:noreply, socket |> assign(:filter_priorities, updated) |> run_analytics()}
  end

  def handle_event("clear_priority_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:filter_priorities, MapSet.new())
     |> assign(:priority_filter_search, "")
     |> run_analytics()}
  end

  # --- Date picker ---

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
        socket.assigns.filter_from == "" ->
          {date_s, ""}

        socket.assigns.filter_to == "" ->
          {:ok, start} = Date.from_iso8601(socket.assigns.filter_from)

          if Date.compare(date, start) == :lt,
            do: {date_s, socket.assigns.filter_from},
            else: {socket.assigns.filter_from, date_s}

        true ->
          {date_s, ""}
      end

    {:noreply, socket |> assign(filter_from: from, filter_to: to) |> run_analytics()}
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
        "all" -> {"", ""}
        _ -> {"", ""}
      end

    {:noreply, socket |> assign(filter_from: from, filter_to: to, show_date_picker: false) |> run_analytics()}
  end

  def handle_event("clear_date_range", _, socket) do
    {:noreply, socket |> assign(filter_from: "", filter_to: "") |> run_analytics()}
  end

  # --- Location events ---

  def handle_event("toggle_location", %{"id" => id}, socket) do
    selected = socket.assigns.selected_location_ids

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    socket =
      socket
      |> assign(:selected_location_ids, selected)
      |> run_analytics()

    {:noreply, socket}
  end

  def handle_event("toggle_loc_expand", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_locations

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded_locations, expanded)}
  end

  def handle_event("clear_locations", _, socket) do
    socket =
      socket
      |> assign(:selected_location_ids, MapSet.new())
      |> run_analytics()

    {:noreply, socket}
  end

  # ==========================================
  # ANALYTICS RUNNER
  # ==========================================

  defp run_analytics(socket) do
    org_id = socket.assigns.org_id

    if org_id do
      selected_ids = MapSet.to_list(socket.assigns.selected_location_ids)

      from_dt = parse_date(socket.assigns.filter_from)
      to_dt = parse_date(socket.assigns.filter_to)

      query =
        Engine.base_query(org_id)
        |> maybe_for_locations(selected_ids)
        |> Engine.in_date_range(from_dt, to_dt)

      # Apply multi-select category filter
      query =
        if MapSet.size(socket.assigns.filter_categories) > 0 do
          cats = MapSet.to_list(socket.assigns.filter_categories)
          where(query, [t], t.category in ^cats)
        else
          query
        end

      # Apply multi-select priority filter
      query =
        if MapSet.size(socket.assigns.filter_priorities) > 0 do
          pris = MapSet.to_list(socket.assigns.filter_priorities)
          where(query, [t], t.priority in ^pris)
        else
          query
        end

      stats = Engine.aggregate_stats(query)
      contractor_perf = Engine.contractor_performance(query)
      location_breakdown = Engine.breakdown_by_location(query)

      socket
      |> assign(:stats, stats)
      |> assign(:contractor_perf, contractor_perf)
      |> assign(:location_breakdown, location_breakdown)
    else
      socket
      |> assign(:stats, empty_stats())
      |> assign(:contractor_perf, [])
      |> assign(:location_breakdown, [])
    end
  end

  defp maybe_for_locations(query, []), do: query
  defp maybe_for_locations(query, ids), do: Engine.for_locations(query, ids)

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      _ -> nil
    end
  end

  defp empty_stats do
    %{
      total: 0,
      by_status: %{},
      by_priority: %{},
      by_category: %{},
      sla_compliance: 100.0,
      sla_total: 0,
      sla_breached: 0,
      avg_resolution_hours: nil
    }
  end

  # ==========================================
  # HELPERS
  # ==========================================

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
    day_of_week = Date.day_of_week(first)
    start_date = Date.add(first, -(day_of_week - 1))
    Enum.map(0..41, fn offset -> Date.add(start_date, offset) end)
  end

  defp in_selected_range?(_date, "", _), do: false
  defp in_selected_range?(_date, _, ""), do: false

  defp in_selected_range?(date, from_str, to_str) do
    with {:ok, from} <- Date.from_iso8601(from_str),
         {:ok, to} <- Date.from_iso8601(to_str) do
      Date.compare(date, from) != :lt && Date.compare(date, to) != :gt
    else
      _ -> false
    end
  end

  defp is_range_endpoint?(_date, "", ""), do: false

  defp is_range_endpoint?(date, from_str, to_str) do
    (from_str != "" && Date.to_iso8601(date) == from_str) ||
      (to_str != "" && Date.to_iso8601(date) == to_str)
  end

  defp format_date_display(""), do: "—"

  defp format_date_display(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
      _ -> date_str
    end
  end

  defp filtered_analytics_categories(categories, ""), do: categories

  defp filtered_analytics_categories(categories, q) do
    q = String.downcase(q)
    Enum.filter(categories, fn cat -> String.contains?(String.downcase(cat), q) end)
  end

  defp filtered_analytics_priorities(priorities, ""), do: priorities

  defp filtered_analytics_priorities(priorities, q) do
    q = String.downcase(q)
    Enum.filter(priorities, fn p -> String.contains?(String.downcase(p), q) end)
  end

  defp stat_bg("blue"), do: "bg-blue-100"
  defp stat_bg("emerald"), do: "bg-emerald-100"
  defp stat_bg("red"), do: "bg-red-100"
  defp stat_bg("sky"), do: "bg-sky-100"
  defp stat_bg(_), do: "bg-base-200"

  defp stat_icon_color("blue"), do: "text-blue-600"
  defp stat_icon_color("emerald"), do: "text-emerald-600"
  defp stat_icon_color("red"), do: "text-red-600"
  defp stat_icon_color("sky"), do: "text-sky-600"
  defp stat_icon_color(_), do: "text-base-content/50"

  defp category_color("hvac"), do: "bg-blue-500"
  defp category_color("plumbing"), do: "bg-cyan-500"
  defp category_color("electrical"), do: "bg-amber-500"
  defp category_color("structural"), do: "bg-red-500"
  defp category_color("appliance"), do: "bg-violet-500"
  defp category_color("furniture"), do: "bg-emerald-500"
  defp category_color("it"), do: "bg-sky-500"
  defp category_color("other"), do: "bg-gray-500"
  defp category_color(_), do: "bg-primary"

  defp category_dot_color("hvac"), do: "bg-blue-500"
  defp category_dot_color("plumbing"), do: "bg-cyan-500"
  defp category_dot_color("electrical"), do: "bg-amber-500"
  defp category_dot_color("structural"), do: "bg-red-500"
  defp category_dot_color("appliance"), do: "bg-violet-500"
  defp category_dot_color("furniture"), do: "bg-emerald-500"
  defp category_dot_color("it"), do: "bg-sky-500"
  defp category_dot_color("other"), do: "bg-gray-500"
  defp category_dot_color(_), do: "bg-primary"

  defp priority_dot_color("emergency"), do: "bg-red-500"
  defp priority_dot_color("high"), do: "bg-orange-500"
  defp priority_dot_color("medium"), do: "bg-yellow-500"
  defp priority_dot_color("low"), do: "bg-blue-500"
  defp priority_dot_color(_), do: "bg-gray-400"
end
