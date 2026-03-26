defmodule FixlyWeb.Admin.ContractorsLive do
  use FixlyWeb, :live_view

  alias Fixly.{Organizations, Tickets}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    socket =
      socket
      |> assign(:page_title, "Contractors")
      |> assign(:org_id, org_id)
      |> assign(:invite_code, "")
      |> assign(:search_results, nil)
      |> assign(:selected_partnership, nil)
      |> assign(:contractor_stats, nil)
      |> assign(:contractor_team_count, nil)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-base-content">Contractor Partnerships</h2>
          <p class="text-sm text-base-content/50">Invite and manage contractor companies</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Invite contractor form -->
        <div class="space-y-4">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
                <.icon name="hero-link" class="size-4" />
                Invite Contractor
              </h3>
            </div>
            <div class="p-5 space-y-4">
              <p class="text-xs text-base-content/50">
                Enter a contractor's display code (e.g. FX-7K4X) or search by name
              </p>
              <form phx-submit="invite_by_code" class="space-y-3">
                <input
                  type="text"
                  name="code"
                  value={@invite_code}
                  placeholder="FX-XXXX or company name"
                  phx-change="search_contractor"
                  phx-debounce="300"
                  class="input input-bordered input-sm w-full font-mono"
                />
                <button type="submit" class="btn btn-primary btn-sm w-full gap-1.5">
                  <.icon name="hero-paper-airplane" class="size-4" />
                  Send Invite
                </button>
              </form>

              <!-- Search results -->
              <div :if={@search_results && @search_results != []} class="space-y-2">
                <p class="text-xs font-medium text-base-content/50">Found contractors:</p>
                <div
                  :for={result <- @search_results}
                  class="flex items-center justify-between p-3 rounded-lg bg-base-200/50 border border-base-200"
                >
                  <div>
                    <p class="text-sm font-medium text-base-content">{result.name}</p>
                    <p class="text-xs text-base-content/50 font-mono">{result.display_code}</p>
                  </div>
                  <button
                    phx-click="invite_org"
                    phx-value-org-id={result.id}
                    class="btn btn-xs btn-primary"
                  >
                    Invite
                  </button>
                </div>
              </div>
              <p :if={@search_results == []} class="text-xs text-base-content/40 text-center py-2">
                No contractors found
              </p>
            </div>
          </div>
        </div>

        <!-- Partnerships list -->
        <div class="lg:col-span-2">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Partnerships
                <span class="badge badge-sm badge-ghost ml-1">{length(@partnerships)}</span>
              </h3>
            </div>
            <div class="divide-y divide-base-200">
              <div
                :for={partnership <- @partnerships}
                phx-click="select_contractor"
                phx-value-id={partnership.id}
                class={[
                  "px-5 py-4 flex items-center justify-between cursor-pointer transition-colors",
                  @selected_partnership && @selected_partnership.id == partnership.id && "bg-primary/5",
                  "hover:bg-base-200/50"
                ]}
              >
                <div class="flex items-center gap-3">
                  <%= if partnership.contractor_org.logo_url do %>
                    <div class="w-10 h-10 rounded-lg overflow-hidden border border-base-200">
                      <img
                        src={partnership.contractor_org.logo_url}
                        alt={partnership.contractor_org.name}
                        class="w-full h-full object-cover"
                      />
                    </div>
                  <% else %>
                    <div class={[
                      "w-10 h-10 rounded-lg flex items-center justify-center",
                      partnership.status == "active" && "bg-success/10",
                      partnership.status == "pending" && "bg-warning/10",
                      partnership.status not in ["active", "pending"] && "bg-base-200"
                    ]}>
                      <.icon name="hero-building-storefront" class={[
                        "size-5",
                        partnership.status == "active" && "text-success",
                        partnership.status == "pending" && "text-warning",
                        partnership.status not in ["active", "pending"] && "text-base-content/30"
                      ]} />
                    </div>
                  <% end %>
                  <div>
                    <p class={[
                      "text-sm font-medium",
                      partnership.status == "inactive" && "text-base-content/50 line-through",
                      partnership.status != "inactive" && "text-base-content"
                    ]}>
                      {partnership.contractor_org.name}
                    </p>
                    <div class="flex items-center gap-2">
                      <span class="text-xs text-base-content/40 font-mono">
                        {partnership.contractor_org.display_code}
                      </span>
                      <span class="text-xs text-base-content/40">
                        · {Calendar.strftime(partnership.inserted_at, "%b %d, %Y")}
                      </span>
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class={[
                    "badge badge-sm",
                    partnership.status == "active" && "badge-success",
                    partnership.status == "pending" && "badge-warning",
                    partnership.status not in ["active", "pending"] && "badge-ghost"
                  ]}>
                    {partnership.status}
                  </span>
                  <button
                    :if={partnership.status == "active"}
                    phx-click="deactivate"
                    phx-value-id={partnership.id}
                    data-confirm="Deactivate this contractor partnership?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
              <div :if={@partnerships == []} class="px-5 py-12 text-center">
                <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-building-storefront" class="size-6 text-base-content/30" />
                </div>
                <h3 class="text-base font-semibold text-base-content mb-1">No contractors yet</h3>
                <p class="text-sm text-base-content/50">Invite a contractor by their display code to get started.</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Contractor detail panel -->
      <div :if={@selected_partnership} class="space-y-6">
        <% org = @selected_partnership.contractor_org %>
        <% stats = @contractor_stats %>

        <!-- Header -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="p-6">
            <div class="flex items-start justify-between">
              <div class="flex items-center gap-4">
                <%= if org.logo_url do %>
                  <div class="w-16 h-16 rounded-xl overflow-hidden border border-base-200">
                    <img src={org.logo_url} alt={org.name} class="w-full h-full object-cover" />
                  </div>
                <% else %>
                  <div class="w-16 h-16 rounded-xl bg-primary/10 flex items-center justify-center">
                    <span class="text-xl font-bold text-primary">
                      {org.name |> String.first() |> String.upcase()}
                    </span>
                  </div>
                <% end %>
                <div>
                  <h3 class="text-lg font-semibold text-base-content">{org.name}</h3>
                  <div class="flex items-center gap-3 mt-1">
                    <span class="text-xs text-base-content/40 font-mono">{org.display_code}</span>
                    <span class={[
                      "badge badge-sm",
                      @selected_partnership.status == "active" && "badge-success",
                      @selected_partnership.status == "pending" && "badge-warning",
                      @selected_partnership.status not in ["active", "pending"] && "badge-ghost"
                    ]}>
                      {@selected_partnership.status}
                    </span>
                    <span class="text-xs text-base-content/40">
                      Partner since {Calendar.strftime(@selected_partnership.inserted_at, "%b %d, %Y")}
                    </span>
                  </div>
                </div>
              </div>
              <button phx-click="close_detail" class="btn btn-ghost btn-sm btn-square">
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <!-- About -->
            <div :if={org.about && org.about != ""} class="mt-4 pt-4 border-t border-base-200">
              <p class="text-xs font-medium text-base-content/50 mb-1">About</p>
              <p class="text-sm text-base-content/70 whitespace-pre-line">{org.about}</p>
            </div>

            <!-- Contact info -->
            <div class="mt-4 pt-4 border-t border-base-200 flex flex-wrap gap-x-6 gap-y-2">
              <div :if={org.email && org.email != ""} class="flex items-center gap-1.5">
                <.icon name="hero-envelope" class="size-3.5 text-base-content/40" />
                <span class="text-sm text-base-content/70">{org.email}</span>
              </div>
              <div :if={org.phone && org.phone != ""} class="flex items-center gap-1.5">
                <.icon name="hero-phone" class="size-3.5 text-base-content/40" />
                <span class="text-sm text-base-content/70">{org.phone}</span>
              </div>
              <div :if={org.address && org.address != ""} class="flex items-center gap-1.5">
                <.icon name="hero-map-pin" class="size-3.5 text-base-content/40" />
                <span class="text-sm text-base-content/70">{org.address}</span>
              </div>
              <div class="flex items-center gap-1.5">
                <.icon name="hero-users" class="size-3.5 text-base-content/40" />
                <span class="text-sm text-base-content/70">{@contractor_team_count} team members</span>
              </div>
              <div class="flex items-center gap-1.5">
                <.icon name="hero-clock" class="size-3.5 text-base-content/40" />
                <span class="text-sm text-base-content/70">{partnership_duration(@selected_partnership)} partnership</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Stats grid -->
        <div :if={stats} class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
            <p class="text-xs text-base-content/50 mb-1">Total Tickets</p>
            <p class="text-2xl font-bold text-base-content">{stats.total}</p>
          </div>
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
            <p class="text-xs text-base-content/50 mb-1">Completed</p>
            <p class="text-2xl font-bold text-success">{stats.completed}</p>
          </div>
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
            <p class="text-xs text-base-content/50 mb-1">Active</p>
            <p class="text-2xl font-bold text-info">{stats.active}</p>
          </div>
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
            <p class="text-xs text-base-content/50 mb-1">SLA Compliance</p>
            <p class={[
              "text-2xl font-bold",
              stats.sla_compliance_rate >= 90 && "text-success",
              stats.sla_compliance_rate >= 70 && stats.sla_compliance_rate < 90 && "text-warning",
              stats.sla_compliance_rate < 70 && "text-error"
            ]}>
              {stats.sla_compliance_rate}%
            </p>
          </div>
        </div>

        <!-- Additional details -->
        <div :if={stats} class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <!-- Performance -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h4 class="text-sm font-semibold text-base-content">Performance</h4>
            </div>
            <div class="p-5 space-y-4">
              <div class="flex justify-between items-center">
                <span class="text-sm text-base-content/60">Avg. Resolution Time</span>
                <span class="text-sm font-medium text-base-content">
                  {format_resolution_time(stats.avg_resolution_hours)}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-base-content/60">SLA Breaches</span>
                <span class={[
                  "text-sm font-medium",
                  stats.breached == 0 && "text-success",
                  stats.breached > 0 && "text-error"
                ]}>
                  {stats.breached}
                </span>
              </div>
              <div class="flex justify-between items-center">
                <span class="text-sm text-base-content/60">Completion Rate</span>
                <span class="text-sm font-medium text-base-content">
                  {if stats.total > 0, do: "#{Float.round(stats.completed / stats.total * 100, 1)}%", else: "N/A"}
                </span>
              </div>
            </div>
          </div>

          <!-- Ticket Breakdown -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h4 class="text-sm font-semibold text-base-content">Ticket Breakdown</h4>
            </div>
            <div class="p-5 space-y-3">
              <div :for={
                {status, label, color} <- [
                  {"assigned", "Assigned", "bg-info"},
                  {"in_progress", "In Progress", "bg-primary"},
                  {"on_hold", "On Hold", "bg-warning"},
                  {"completed", "Completed", "bg-success"},
                  {"reviewed", "Reviewed", "bg-accent"},
                  {"closed", "Closed", "bg-neutral"}
                ]
              }>
                <% count = Map.get(stats.status_counts, status, 0) %>
                <div :if={count > 0} class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <div class={"w-2 h-2 rounded-full #{color}"} />
                    <span class="text-sm text-base-content/60">{label}</span>
                  </div>
                  <span class="text-sm font-medium text-base-content">{count}</span>
                </div>
              </div>
              <div :if={stats.total == 0} class="text-sm text-base-content/40 text-center py-2">
                No tickets assigned yet
              </div>
            </div>

            <!-- Priority breakdown -->
            <div :if={map_size(stats.priority_counts) > 0} class="px-5 pb-5">
              <p class="text-xs font-medium text-base-content/50 mb-2 pt-3 border-t border-base-200">By Priority</p>
              <div class="flex gap-2 flex-wrap">
                <span
                  :for={{priority, count} <- stats.priority_counts}
                  class={[
                    "badge badge-sm gap-1",
                    priority == "emergency" && "badge-error",
                    priority == "high" && "badge-warning",
                    priority == "medium" && "badge-info",
                    priority == "low" && "badge-ghost"
                  ]}
                >
                  {priority} · {count}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_contractor", %{"code" => query}, socket) when byte_size(query) >= 2 do
    results = Organizations.search_contractor_orgs(query)
    # Filter out contractors already in partnerships
    existing_ids = Enum.map(socket.assigns.partnerships, & &1.contractor_org.id)
    filtered = Enum.reject(results, &(&1.id in existing_ids))

    {:noreply, assign(socket, search_results: filtered, invite_code: query)}
  end

  def handle_event("search_contractor", %{"code" => query}, socket) do
    {:noreply, assign(socket, search_results: nil, invite_code: query)}
  end

  def handle_event("invite_by_code", %{"code" => code}, socket) do
    org_id = socket.assigns.org_id

    case Organizations.get_contractor_by_code(code) do
      nil ->
        {:noreply, put_flash(socket, :error, "No contractor found with code #{code}")}

      contractor ->
        send_invite(socket, org_id, contractor)
    end
  end

  def handle_event("invite_org", %{"org-id" => contractor_org_id}, socket) do
    send_invite(socket, socket.assigns.org_id, %{id: contractor_org_id})
  end

  def handle_event("select_contractor", %{"id" => partnership_id}, socket) do
    partnership = Enum.find(socket.assigns.partnerships, &(&1.id == partnership_id))

    if partnership do
      contractor_org_id = partnership.contractor_org.id
      owner_org_id = socket.assigns.org_id

      stats = Tickets.contractor_stats_for_owner(contractor_org_id, owner_org_id)
      team_count = Organizations.count_team_members(contractor_org_id)

      {:noreply,
       socket
       |> assign(:selected_partnership, partnership)
       |> assign(:contractor_stats, stats)
       |> assign(:contractor_team_count, team_count)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_partnership, nil)
     |> assign(:contractor_stats, nil)
     |> assign(:contractor_team_count, nil)}
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    case Organizations.deactivate_partnership(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Partnership deactivated")
         |> assign(:selected_partnership, nil)
         |> assign(:contractor_stats, nil)
         |> assign(:contractor_team_count, nil)
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate partnership")}
    end
  end

  defp send_invite(socket, owner_org_id, contractor) do
    case Organizations.send_partnership_invite(owner_org_id, contractor.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Partnership invite sent!")
         |> assign(:invite_code, "")
         |> assign(:search_results, nil)
         |> reload_data()}

      {:error, :already_active} ->
        {:noreply, put_flash(socket, :error, "Partnership already active")}

      {:error, :already_pending} ->
        {:noreply, put_flash(socket, :error, "Invite already pending")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send invite")}
    end
  end

  defp reload_data(socket) do
    org_id = socket.assigns.org_id
    partnerships = if org_id, do: Organizations.list_partnerships(org_id), else: []
    assign(socket, :partnerships, partnerships)
  end

  defp partnership_duration(partnership) do
    days = Date.diff(Date.utc_today(), DateTime.to_date(partnership.inserted_at))

    cond do
      days < 1 -> "< 1 day"
      days == 1 -> "1 day"
      days < 30 -> "#{days} days"
      days < 365 ->
        months = div(days, 30)
        if months == 1, do: "1 month", else: "#{months} months"
      true ->
        years = div(days, 365)
        remaining_months = div(rem(days, 365), 30)
        year_str = if years == 1, do: "1 year", else: "#{years} years"
        if remaining_months > 0, do: "#{year_str}, #{remaining_months}mo", else: year_str
    end
  end

  defp format_resolution_time(nil), do: "N/A"
  defp format_resolution_time(hours) when hours < 1, do: "< 1 hour"
  defp format_resolution_time(hours) when hours < 24, do: "#{Float.round(hours, 1)} hours"
  defp format_resolution_time(hours) do
    days = Float.round(hours / 24, 1)
    "#{days} days"
  end
end
