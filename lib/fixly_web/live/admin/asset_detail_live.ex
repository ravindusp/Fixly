defmodule FixlyWeb.Admin.AssetDetailLive do
  use FixlyWeb, :live_view

  alias Fixly.Assets

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    asset = Assets.get_asset!(id)
    linked_tickets = Assets.list_tickets_for_asset(id)
    activity_log = Assets.list_activity_for_asset(id)

    active_ticket_count = Enum.count(linked_tickets, fn t -> t.status not in ["closed", "completed", "reviewed"] end)

    socket =
      socket
      |> assign(:page_title, asset.name)
      |> assign(:asset, asset)
      |> assign(:linked_tickets, linked_tickets)
      |> assign(:activity_log, activity_log)
      |> assign(:active_ticket_count, active_ticket_count)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Back nav -->
      <div class="flex items-center gap-3">
        <.link navigate={~p"/admin/assets"} class="btn btn-sm btn-ghost gap-1.5">
          <.icon name="hero-arrow-left" class="size-4" /> Assets
        </.link>
      </div>

      <div class="flex gap-6">
        <!-- Left column (main) -->
        <div class="flex-1 min-w-0 space-y-6">
          <!-- Asset header -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-6">
            <div class="flex items-start justify-between gap-4">
              <div class="flex items-center gap-4">
                <div class={["w-14 h-14 rounded-2xl flex items-center justify-center", category_bg(@asset.category)]}>
                  <.icon name={category_icon(@asset.category)} class={["size-7", category_color(@asset.category)]} />
                </div>
                <div>
                  <h1 class="text-2xl font-bold text-base-content">{@asset.name}</h1>
                  <div class="flex items-center gap-2 mt-1.5">
                    <span :if={@asset.category} class="badge badge-sm badge-ghost">{String.capitalize(@asset.category)}</span>
                    <.asset_status_badge status={@asset.status} />
                    <span :if={@asset.location} class="flex items-center gap-1 text-sm text-base-content/60">
                      <.icon name="hero-map-pin" class="size-3.5" />
                      {@asset.location.name}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Description / Metadata -->
            <div :if={@asset.metadata != %{} and @asset.metadata != nil} class="mt-4 bg-base-200/40 rounded-lg p-4">
              <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Metadata</p>
              <div class="grid grid-cols-2 gap-2">
                <div :for={{key, value} <- @asset.metadata} class="flex justify-between text-sm">
                  <span class="text-base-content/50">{key}</span>
                  <span class="text-base-content">{value}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Linked Tickets -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <h2 class="text-sm font-semibold text-base-content">Linked Tickets</h2>
                <span class="badge badge-sm badge-ghost">{length(@linked_tickets)}</span>
              </div>
            </div>

            <%= if @linked_tickets == [] do %>
              <div class="flex flex-col items-center justify-center py-12 text-center">
                <div class="w-12 h-12 rounded-2xl bg-base-200 flex items-center justify-center mb-3">
                  <.icon name="hero-ticket" class="size-5 text-base-content/30" />
                </div>
                <p class="text-sm text-base-content/50">No tickets linked to this asset yet.</p>
              </div>
            <% else %>
              <!-- Header -->
              <div class="grid grid-cols-[1fr_2fr_1fr_1fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
                <span>Reference</span><span>Description</span><span>Status</span><span>Priority</span><span>Date</span>
              </div>
              <!-- Rows -->
              <.link
                :for={ticket <- @linked_tickets}
                navigate={~p"/admin/tickets/#{ticket.id}"}
                class="grid grid-cols-[1fr_2fr_1fr_1fr_1fr] gap-4 px-5 py-3 border-b border-base-200 items-center hover:bg-base-200/30 transition-colors"
              >
                <span class="text-sm font-mono text-base-content">{ticket.reference_number}</span>
                <p class="text-sm text-base-content/70 truncate">{ticket.description}</p>
                <div><.ticket_status_badge status={ticket.status} /></div>
                <div><.ticket_priority_badge priority={ticket.priority} /></div>
                <span class="text-sm text-base-content/60">{format_date(ticket.inserted_at)}</span>
              </.link>
            <% end %>
          </div>

          <!-- Activity Log -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Activity Log</h2>
            </div>

            <%= if @activity_log == [] do %>
              <div class="flex flex-col items-center justify-center py-12 text-center">
                <div class="w-12 h-12 rounded-2xl bg-base-200 flex items-center justify-center mb-3">
                  <.icon name="hero-clock" class="size-5 text-base-content/30" />
                </div>
                <p class="text-sm text-base-content/50">No activity recorded yet.</p>
              </div>
            <% else %>
              <div class="p-5">
                <div class="relative">
                  <!-- Timeline line -->
                  <div class="absolute left-4 top-0 bottom-0 w-px bg-base-300"></div>

                  <div :for={event <- @activity_log} class="relative flex gap-4 pb-5 last:pb-0">
                    <!-- Timeline dot -->
                    <div class={[
                      "relative z-10 w-8 h-8 rounded-full flex items-center justify-center shrink-0",
                      activity_dot_bg(event.type)
                    ]}>
                      <.icon name={activity_icon(event.type)} class={["size-3.5", activity_icon_color(event.type)]} />
                    </div>

                    <!-- Content -->
                    <div class="flex-1 min-w-0 pt-0.5">
                      <div class="flex items-center gap-2 mb-0.5">
                        <span class="text-xs font-semibold text-base-content">
                          {event_author(event)}
                        </span>
                        <span class="text-[10px] text-base-content/40">
                          {Calendar.strftime(event.inserted_at, "%b %d, %Y at %I:%M %p")}
                        </span>
                      </div>
                      <p class={[
                        "text-sm leading-relaxed",
                        event.type == "comment" && "text-base-content/70",
                        event.type != "comment" && "text-base-content/50"
                      ]}>
                        {event.body}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Right column (sidebar) -->
        <div class="w-full lg:w-[320px] shrink-0 space-y-5">
          <!-- Quick stats -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">Quick Stats</h3>
            <div class="space-y-3">
              <div class="flex justify-between text-sm">
                <span class="text-base-content/50">Total Tickets</span>
                <span class="font-semibold text-base-content">{length(@linked_tickets)}</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-base-content/50">Active Tickets</span>
                <span class="font-semibold text-warning">{@active_ticket_count}</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-base-content/50">Total Repair Cost</span>
                <span class="font-semibold text-base-content">${@asset.total_repair_cost || 0}</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-base-content/50">Created</span>
                <span class="text-base-content">{Calendar.strftime(@asset.inserted_at, "%b %d, %Y")}</span>
              </div>
              <div class="flex justify-between text-sm">
                <span class="text-base-content/50">Created via</span>
                <span class={["text-sm", @asset.created_via != "manual" && "text-accent"]}>
                  {String.capitalize(@asset.created_via || "manual")}
                </span>
              </div>
              <div :if={@asset.ai_confidence} class="flex justify-between text-sm">
                <span class="text-base-content/50">AI Confidence</span>
                <span>{Float.round(@asset.ai_confidence * 100, 0)}%</span>
              </div>
            </div>
          </div>

          <!-- Status change -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">Change Status</h3>
            <div class="flex flex-wrap gap-1.5">
              <button
                :for={{s, label} <- [{"operational", "Operational"}, {"needs_attention", "Needs Attention"}, {"needs_repair", "Needs Repair"}, {"out_of_service", "Out of Service"}, {"retired", "Retired"}]}
                phx-click="update_status"
                phx-value-status={s}
                class={["btn btn-xs", @asset.status == s && "btn-primary", @asset.status != s && "btn-ghost"]}
              >
                {label}
              </button>
            </div>
          </div>

          <!-- Location info -->
          <div :if={@asset.location} class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">Location</h3>
            <div class="flex items-center gap-2 text-sm text-base-content mb-3">
              <.icon name="hero-map-pin" class="size-4 text-base-content/40" />
              <span>{@asset.location.name}</span>
            </div>
            <a
              href={maps_url_for_location(@asset.location)}
              target="_blank"
              class="btn btn-sm btn-outline w-full gap-2"
            >
              <.icon name="hero-map" class="size-4" />
              Navigate
            </a>
          </div>

          <!-- QR Code -->
          <div :if={@asset.qr_code_id} class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">QR Code</h3>
            <div class="flex items-center gap-2 text-sm text-base-content">
              <.icon name="hero-qr-code" class="size-5 text-base-content/40" />
              <span class="font-mono text-xs">{@asset.qr_code_id}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("update_status", %{"status" => status}, socket) do
    {:ok, asset} = Assets.update_asset(socket.assigns.asset, %{status: status})
    asset = Assets.get_asset!(asset.id)
    {:noreply, assign(socket, :asset, asset)}
  end

  # --- Components ---

  attr :status, :string, required: true
  defp asset_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @status == "operational" && "badge-success",
      @status == "needs_attention" && "badge-info",
      @status == "needs_repair" && "badge-warning",
      @status == "out_of_service" && "badge-error",
      @status == "retired" && "badge-ghost"
    ]}>{asset_status_label(@status)}</span>
    """
  end

  attr :status, :string, required: true
  defp ticket_status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm font-medium", ticket_status_class(@status)]}>{ticket_status_label(@status)}</span>
    """
  end

  attr :priority, :string, default: nil
  defp ticket_priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={["badge badge-sm font-medium", priority_class(@priority)]}>
      {String.capitalize(@priority)}
    </span>
    <span :if={!@priority} class="text-xs text-base-content/30">--</span>
    """
  end

  # --- Helpers ---

  defp asset_status_label("operational"), do: "Operational"
  defp asset_status_label("needs_attention"), do: "Needs Attention"
  defp asset_status_label("needs_repair"), do: "Needs Repair"
  defp asset_status_label("out_of_service"), do: "Out of Service"
  defp asset_status_label("retired"), do: "Retired"
  defp asset_status_label(other), do: String.capitalize(to_string(other))

  defp ticket_status_label("created"), do: "Open"
  defp ticket_status_label("triaged"), do: "Triaged"
  defp ticket_status_label("assigned"), do: "Assigned"
  defp ticket_status_label("in_progress"), do: "In Progress"
  defp ticket_status_label("on_hold"), do: "On Hold"
  defp ticket_status_label("completed"), do: "Completed"
  defp ticket_status_label("reviewed"), do: "Reviewed"
  defp ticket_status_label("closed"), do: "Closed"
  defp ticket_status_label(other), do: String.capitalize(to_string(other))

  defp ticket_status_class("created"), do: "badge-success badge-outline"
  defp ticket_status_class("triaged"), do: "badge-info badge-outline"
  defp ticket_status_class("assigned"), do: "badge-primary badge-outline"
  defp ticket_status_class("in_progress"), do: "badge-info"
  defp ticket_status_class("on_hold"), do: "badge-warning"
  defp ticket_status_class("completed"), do: "badge-success"
  defp ticket_status_class(_), do: "badge-ghost"

  defp priority_class("emergency"), do: "badge-error"
  defp priority_class("high"), do: "badge-warning"
  defp priority_class("medium"), do: "bg-amber-100 text-amber-700 border-amber-200"
  defp priority_class(_), do: "badge-ghost"

  defp format_date(nil), do: ""
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  defp category_icon("hvac"), do: "hero-fire"
  defp category_icon("plumbing"), do: "hero-beaker"
  defp category_icon("electrical"), do: "hero-bolt"
  defp category_icon("structural"), do: "hero-home"
  defp category_icon("appliance"), do: "hero-cog-6-tooth"
  defp category_icon("furniture"), do: "hero-cube"
  defp category_icon("it"), do: "hero-computer-desktop"
  defp category_icon(_), do: "hero-wrench"

  defp category_bg("hvac"), do: "bg-red-100"
  defp category_bg("plumbing"), do: "bg-blue-100"
  defp category_bg("electrical"), do: "bg-yellow-100"
  defp category_bg("structural"), do: "bg-stone-100"
  defp category_bg("appliance"), do: "bg-purple-100"
  defp category_bg("furniture"), do: "bg-emerald-100"
  defp category_bg("it"), do: "bg-cyan-100"
  defp category_bg(_), do: "bg-base-200"

  defp category_color("hvac"), do: "text-red-600"
  defp category_color("plumbing"), do: "text-blue-600"
  defp category_color("electrical"), do: "text-yellow-600"
  defp category_color("structural"), do: "text-stone-600"
  defp category_color("appliance"), do: "text-purple-600"
  defp category_color("furniture"), do: "text-emerald-600"
  defp category_color("it"), do: "text-cyan-600"
  defp category_color(_), do: "text-base-content/50"

  defp activity_icon("comment"), do: "hero-chat-bubble-left"
  defp activity_icon("status_change"), do: "hero-arrow-path"
  defp activity_icon("assignment"), do: "hero-user-plus"
  defp activity_icon("priority_change"), do: "hero-flag"
  defp activity_icon("category_change"), do: "hero-tag"
  defp activity_icon("asset_linked"), do: "hero-link"
  defp activity_icon("sla_breach"), do: "hero-exclamation-triangle"
  defp activity_icon("created"), do: "hero-plus-circle"
  defp activity_icon("system"), do: "hero-cog-6-tooth"
  defp activity_icon(_), do: "hero-information-circle"

  defp activity_dot_bg("comment"), do: "bg-base-200"
  defp activity_dot_bg("status_change"), do: "bg-info/10"
  defp activity_dot_bg("assignment"), do: "bg-primary/10"
  defp activity_dot_bg("priority_change"), do: "bg-warning/10"
  defp activity_dot_bg("sla_breach"), do: "bg-error/10"
  defp activity_dot_bg("asset_linked"), do: "bg-success/10"
  defp activity_dot_bg("created"), do: "bg-success/10"
  defp activity_dot_bg(_), do: "bg-base-200"

  defp activity_icon_color("comment"), do: "text-base-content/50"
  defp activity_icon_color("status_change"), do: "text-info"
  defp activity_icon_color("assignment"), do: "text-primary"
  defp activity_icon_color("priority_change"), do: "text-warning"
  defp activity_icon_color("sla_breach"), do: "text-error"
  defp activity_icon_color("asset_linked"), do: "text-success"
  defp activity_icon_color("created"), do: "text-success"
  defp activity_icon_color(_), do: "text-base-content/40"

  defp event_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp event_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp event_author(_), do: "System"

  defp maps_url_for_location(location) do
    cond do
      location.metadata["gps_lat"] && location.metadata["gps_lng"] ->
        lat = location.metadata["gps_lat"]
        lng = location.metadata["gps_lng"]
        "https://www.google.com/maps/search/?api=1&query=#{lat},#{lng}"

      true ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(location.name)}"
    end
  end
end
