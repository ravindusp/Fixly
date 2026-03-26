defmodule FixlyWeb.Admin.DashboardLive do
  use FixlyWeb, :live_view

  alias Fixly.Analytics.Engine
  alias Fixly.Tickets

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    if org_id do
      query = Engine.base_query(org_id)
      stats = Engine.aggregate_stats(query)
      contractor_perf = Engine.contractor_performance(query)
      volume = Engine.group_by_period(query, :day)

      recent_tickets = Tickets.list_recent_tickets(org_id, 5)
      overdue_tickets = Tickets.list_overdue_tickets(org_id)

      socket =
        socket
        |> assign(:page_title, "Dashboard")
        |> assign(:org_id, org_id)
        |> assign(:stats, stats)
        |> assign(:contractor_perf, contractor_perf)
        |> assign(:volume, volume)
        |> assign(:recent_tickets, recent_tickets)
        |> assign(:overdue_tickets, overdue_tickets)
        |> assign(:overdue_count, length(overdue_tickets))

      {:ok, socket}
    else
      socket =
        socket
        |> assign(:page_title, "Dashboard")
        |> assign(:org_id, nil)
        |> assign(:stats, empty_stats())
        |> assign(:contractor_perf, [])
        |> assign(:volume, [])
        |> assign(:recent_tickets, [])
        |> assign(:overdue_tickets, [])
        |> assign(:overdue_count, 0)

      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Page Header -->
      <div>
        <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
        <p class="text-sm text-base-content/50 mt-1">Overview of your maintenance operations</p>
      </div>

      <!-- Stat Cards -->
      <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-4">
        <.stat_card
          label="Total Tickets"
          value={@stats.total}
          icon="hero-ticket"
          color="blue"
        />
        <.stat_card
          label="Open"
          value={Map.get(@stats.by_status, "created", 0) + Map.get(@stats.by_status, "triaged", 0)}
          icon="hero-inbox"
          color="amber"
        />
        <.stat_card
          label="In Progress"
          value={Map.get(@stats.by_status, "in_progress", 0) + Map.get(@stats.by_status, "assigned", 0)}
          icon="hero-wrench-screwdriver"
          color="violet"
        />
        <.stat_card
          label="On Hold"
          value={Map.get(@stats.by_status, "on_hold", 0)}
          icon="hero-pause-circle"
          color="orange"
        />
        <.stat_card
          label="SLA Compliance"
          value={"#{@stats.sla_compliance}%"}
          icon="hero-shield-check"
          color={if @stats.sla_compliance >= 90, do: "emerald", else: "red"}
        />
        <.stat_card
          label="Avg Resolution"
          value={if @stats.avg_resolution_hours, do: "#{@stats.avg_resolution_hours}h", else: "--"}
          icon="hero-clock"
          color="sky"
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Left column (2/3 width) -->
        <div class="lg:col-span-2 space-y-6">
          <!-- Ticket Volume Chart Placeholder -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Ticket Volume (30 Days)</h2>
            </div>
            <div class="p-5">
              <div class="h-64 flex items-center justify-center">
                <%= if @volume == [] do %>
                  <div class="text-center">
                    <.icon name="hero-chart-bar" class="size-10 text-base-content/20 mx-auto mb-2" />
                    <p class="text-sm text-base-content/40">No ticket data yet</p>
                  </div>
                <% else %>
                  <% entries = Enum.take(@volume, -30) %>
                  <% max_count = entries |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end) %>
                  <div class="w-full h-48 flex flex-col">
                    <div class="flex-1 flex items-end gap-0.5">
                      <%= for entry <- entries do %>
                        <% height_pct = if max_count > 0, do: entry.count / max_count * 100.0, else: 0 %>
                        <div
                          class="flex-1 bg-primary/60 rounded-t hover:bg-primary transition-colors min-w-[3px] group relative"
                          style={"height: #{max(height_pct, 3)}%"}
                        >
                          <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-1 hidden group-hover:block bg-base-content text-base-100 text-[10px] px-1.5 py-0.5 rounded whitespace-nowrap">
                            {entry.count}
                          </div>
                        </div>
                      <% end %>
                    </div>
                    <div class="flex justify-between mt-2 text-[10px] text-base-content/30">
                      <span>{Calendar.strftime(List.first(entries).date, "%b %d")}</span>
                      <span>{Calendar.strftime(List.last(entries).date, "%b %d")}</span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Category Breakdown -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Tickets by Category</h2>
            </div>
            <div class="p-5">
              <%= if @stats.by_category == %{} do %>
                <div class="text-center py-8">
                  <p class="text-sm text-base-content/40">No categorized tickets yet</p>
                </div>
              <% else %>
                <% total_cat = @stats.by_category |> Map.values() |> Enum.sum() |> max(1) %>
                <div class="space-y-3">
                  <%= for {category, count} <- Enum.sort_by(@stats.by_category, fn {_k, v} -> -v end) do %>
                    <% pct = Float.round(count / total_cat * 100.0, 1) %>
                    <div>
                      <div class="flex items-center justify-between mb-1">
                        <span class="text-sm font-medium text-base-content capitalize">{category}</span>
                        <span class="text-xs text-base-content/50">{count} <span class="text-base-content/30">({pct}%)</span></span>
                      </div>
                      <div class="h-2 bg-base-200 rounded-full overflow-hidden">
                        <div
                          class={"h-full rounded-full #{category_bar_color(category)}"}
                          style={"width: #{max(pct, 1)}%"}
                        >
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Contractor Leaderboard -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Contractor Performance</h2>
            </div>
            <%= if @contractor_perf == [] do %>
              <div class="p-5 text-center py-8">
                <p class="text-sm text-base-content/40">No contractor assignments yet</p>
              </div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr class="text-base-content/50">
                      <th>Contractor</th>
                      <th class="text-right">Total</th>
                      <th class="text-right">Completed</th>
                      <th class="text-right">SLA Compliance</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for cp <- @contractor_perf do %>
                      <% compliance = if cp.total > 0, do: Float.round((cp.total - cp.breached) / cp.total * 100, 1), else: 100.0 %>
                      <tr class="hover:bg-base-200/30">
                        <td class="font-medium text-base-content">{cp.org_name}</td>
                        <td class="text-right text-base-content/70">{cp.total}</td>
                        <td class="text-right text-base-content/70">{cp.completed}</td>
                        <td class="text-right">
                          <span class={[
                            "text-sm font-medium",
                            compliance >= 90 && "text-success",
                            compliance >= 70 && compliance < 90 && "text-warning",
                            compliance < 70 && "text-error"
                          ]}>
                            {compliance}%
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

        <!-- Right column (1/3 width) -->
        <div class="space-y-6">
          <!-- Overdue Tickets -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-base-content">Overdue Tickets</h2>
              <span :if={@overdue_count > 0} class="badge badge-error badge-sm">{@overdue_count}</span>
            </div>
            <div class="p-5">
              <%= if @overdue_tickets == [] do %>
                <div class="text-center py-6">
                  <div class="w-10 h-10 rounded-xl bg-success/10 flex items-center justify-center mx-auto mb-3">
                    <.icon name="hero-check-circle" class="size-5 text-success" />
                  </div>
                  <p class="text-sm text-base-content/50">No overdue tickets</p>
                </div>
              <% else %>
                <div class="space-y-3">
                  <%= for ticket <- Enum.take(@overdue_tickets, 5) do %>
                    <.link
                      navigate={~p"/admin/tickets/#{ticket.id}"}
                      class="block p-3 rounded-lg border border-error/20 bg-error/5 hover:bg-error/10 transition-colors"
                    >
                      <div class="flex items-center gap-2 mb-1">
                        <span class="text-xs font-mono text-base-content/40">{ticket.reference_number}</span>
                        <.priority_pill priority={ticket.priority} />
                      </div>
                      <p class="text-sm text-base-content line-clamp-2">{truncate_text(ticket.description, 80)}</p>
                      <p :if={ticket.sla_deadline} class="text-xs text-error mt-1">
                        Deadline: {Calendar.strftime(ticket.sla_deadline, "%b %d, %H:%M")}
                      </p>
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Recent Tickets -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-base-content">Recent Tickets</h2>
              <.link navigate={~p"/admin/tickets"} class="text-xs text-primary hover:underline">
                View all
              </.link>
            </div>
            <div class="divide-y divide-base-300">
              <%= if @recent_tickets == [] do %>
                <div class="p-5 text-center py-8">
                  <p class="text-sm text-base-content/40">No tickets yet</p>
                </div>
              <% else %>
                <%= for ticket <- @recent_tickets do %>
                  <.link
                    navigate={~p"/admin/tickets/#{ticket.id}"}
                    class="block px-5 py-3 hover:bg-base-200/30 transition-colors"
                  >
                    <div class="flex items-center justify-between gap-2">
                      <div class="min-w-0 flex-1">
                        <div class="flex items-center gap-2 mb-0.5">
                          <span class="text-xs font-mono text-base-content/40">{ticket.reference_number}</span>
                          <.status_dot status={ticket.status} />
                        </div>
                        <p class="text-sm text-base-content truncate">{truncate_text(ticket.description, 60)}</p>
                      </div>
                      <span class="text-xs text-base-content/40 shrink-0">
                        {relative_time(ticket.inserted_at)}
                      </span>
                    </div>
                  </.link>
                <% end %>
              <% end %>
            </div>
          </div>

          <!-- Priority Breakdown -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-4 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">By Priority</h2>
            </div>
            <div class="p-5 space-y-3">
              <.priority_row label="Emergency" count={Map.get(@stats.by_priority, "emergency", 0)} color="bg-red-500" />
              <.priority_row label="High" count={Map.get(@stats.by_priority, "high", 0)} color="bg-orange-500" />
              <.priority_row label="Medium" count={Map.get(@stats.by_priority, "medium", 0)} color="bg-yellow-500" />
              <.priority_row label="Low" count={Map.get(@stats.by_priority, "low", 0)} color="bg-blue-500" />
            </div>
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
  attr :icon, :string, required: true
  attr :color, :string, default: "blue"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
      <div class="flex items-center justify-between mb-3">
        <div class={[
          "w-9 h-9 rounded-lg flex items-center justify-center",
          stat_card_bg(@color)
        ]}>
          <.icon name={@icon} class={"size-4 #{stat_card_icon_color(@color)}"} />
        </div>
      </div>
      <p class="text-2xl font-bold text-base-content">{@value}</p>
      <p class="text-xs font-medium text-base-content/50 mt-1">{@label}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :color, :string, required: true

  defp priority_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div class="flex items-center gap-2">
        <div class={"w-2.5 h-2.5 rounded-full #{@color}"}></div>
        <span class="text-sm text-base-content">{@label}</span>
      </div>
      <span class="text-sm font-semibold text-base-content">{@count}</span>
    </div>
    """
  end

  attr :priority, :string, default: nil

  defp priority_pill(assigns) do
    ~H"""
    <span
      :if={@priority}
      class={[
        "badge badge-sm",
        @priority == "emergency" && "badge-error",
        @priority == "high" && "badge-warning",
        @priority == "medium" && "badge-info",
        @priority == "low" && "badge-ghost"
      ]}
    >
      {@priority}
    </span>
    """
  end

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "w-2 h-2 rounded-full inline-block",
      @status in ["created", "triaged"] && "bg-blue-500",
      @status in ["assigned", "in_progress"] && "bg-violet-500",
      @status == "on_hold" && "bg-amber-500",
      @status in ["completed", "reviewed", "closed"] && "bg-emerald-500"
    ]}>
    </span>
    """
  end

  # ==========================================
  # HELPERS
  # ==========================================

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

  defp truncate_text(nil, _), do: ""
  defp truncate_text(text, max_len) when byte_size(text) <= max_len, do: text
  defp truncate_text(text, max_len), do: String.slice(text, 0, max_len) <> "..."

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp stat_card_bg("blue"), do: "bg-blue-100"
  defp stat_card_bg("amber"), do: "bg-amber-100"
  defp stat_card_bg("violet"), do: "bg-violet-100"
  defp stat_card_bg("orange"), do: "bg-orange-100"
  defp stat_card_bg("emerald"), do: "bg-emerald-100"
  defp stat_card_bg("red"), do: "bg-red-100"
  defp stat_card_bg("sky"), do: "bg-sky-100"
  defp stat_card_bg(_), do: "bg-base-200"

  defp stat_card_icon_color("blue"), do: "text-blue-600"
  defp stat_card_icon_color("amber"), do: "text-amber-600"
  defp stat_card_icon_color("violet"), do: "text-violet-600"
  defp stat_card_icon_color("orange"), do: "text-orange-600"
  defp stat_card_icon_color("emerald"), do: "text-emerald-600"
  defp stat_card_icon_color("red"), do: "text-red-600"
  defp stat_card_icon_color("sky"), do: "text-sky-600"
  defp stat_card_icon_color(_), do: "text-base-content/50"

  defp category_bar_color("hvac"), do: "bg-blue-500"
  defp category_bar_color("plumbing"), do: "bg-cyan-500"
  defp category_bar_color("electrical"), do: "bg-amber-500"
  defp category_bar_color("structural"), do: "bg-red-500"
  defp category_bar_color("appliance"), do: "bg-violet-500"
  defp category_bar_color("furniture"), do: "bg-emerald-500"
  defp category_bar_color("it"), do: "bg-sky-500"
  defp category_bar_color("other"), do: "bg-gray-500"
  defp category_bar_color(_), do: "bg-primary"
end
