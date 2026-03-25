defmodule FixlyWeb.Admin.AnalyticsLive do
  use FixlyWeb, :live_view

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
      |> assign(:filter_category, "all")
      |> assign(:filter_priority, "all")
      |> assign(:filter_from, "")
      |> assign(:filter_to, "")
      |> assign(:categories, @categories)
      |> assign(:priorities, @priorities)
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
            <form phx-change="filter_changed" class="flex flex-wrap items-end gap-3">
              <div>
                <label class="text-xs text-base-content/50 mb-1 block">From</label>
                <input
                  type="date"
                  name="from"
                  value={@filter_from}
                  class="input input-sm input-bordered"
                />
              </div>
              <div>
                <label class="text-xs text-base-content/50 mb-1 block">To</label>
                <input
                  type="date"
                  name="to"
                  value={@filter_to}
                  class="input input-sm input-bordered"
                />
              </div>
              <div>
                <label class="text-xs text-base-content/50 mb-1 block">Category</label>
                <select name="category" class="select select-sm select-bordered">
                  <option value="all" selected={@filter_category == "all"}>All Categories</option>
                  <%= for cat <- @categories do %>
                    <option value={cat} selected={@filter_category == cat}>{String.capitalize(cat)}</option>
                  <% end %>
                </select>
              </div>
              <div>
                <label class="text-xs text-base-content/50 mb-1 block">Priority</label>
                <select name="priority" class="select select-sm select-bordered">
                  <option value="all" selected={@filter_priority == "all"}>All Priorities</option>
                  <%= for pri <- @priorities do %>
                    <option value={pri} selected={@filter_priority == pri}>{String.capitalize(pri)}</option>
                  <% end %>
                </select>
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
            </form>
          </div>

          <!-- Stats Summary -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
            <.analytics_stat label="Total Tickets" value={@stats.total} />
            <.analytics_stat label="SLA Compliance" value={"#{@stats.sla_compliance}%"} />
            <.analytics_stat label="Avg Resolution" value={if @stats.avg_resolution_hours, do: "#{@stats.avg_resolution_hours}h", else: "--"} />
            <.analytics_stat label="SLA Breaches" value={@stats.sla_breached} />
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

  defp analytics_stat(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
      <p class="text-xs font-medium text-base-content/50">{@label}</p>
      <p class="text-xl font-bold text-base-content mt-1">{@value}</p>
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
  def handle_event("filter_changed", params, socket) do
    socket =
      socket
      |> assign(:filter_from, params["from"] || "")
      |> assign(:filter_to, params["to"] || "")
      |> assign(:filter_category, params["category"] || "all")
      |> assign(:filter_priority, params["priority"] || "all")
      |> run_analytics()

    {:noreply, socket}
  end

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
        |> Engine.with_category(socket.assigns.filter_category)
        |> Engine.with_priority(socket.assigns.filter_priority)

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

  defp category_color("hvac"), do: "bg-blue-500"
  defp category_color("plumbing"), do: "bg-cyan-500"
  defp category_color("electrical"), do: "bg-amber-500"
  defp category_color("structural"), do: "bg-red-500"
  defp category_color("appliance"), do: "bg-violet-500"
  defp category_color("furniture"), do: "bg-emerald-500"
  defp category_color("it"), do: "bg-sky-500"
  defp category_color("other"), do: "bg-gray-500"
  defp category_color(_), do: "bg-primary"
end
