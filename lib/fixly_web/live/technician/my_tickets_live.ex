defmodule FixlyWeb.Technician.MyTicketsLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    tickets = Tickets.list_user_tickets(user.id)

    socket =
      socket
      |> assign(:page_title, "My Tickets")
      |> assign(:tickets, tickets)
      |> assign(:user, user)
      |> assign(:selected_ticket_id, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-base-content">My Tickets</h2>
          <p class="text-sm text-base-content/50">{length(@tickets)} active tickets assigned to you</p>
        </div>
      </div>

      <%= if @tickets == [] do %>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="flex flex-col items-center justify-center py-16 text-center">
            <div class="w-14 h-14 rounded-2xl bg-success/10 flex items-center justify-center mb-4">
              <.icon name="hero-check-circle" class="size-7 text-success" />
            </div>
            <h3 class="text-base font-semibold text-base-content mb-1">All caught up!</h3>
            <p class="text-sm text-base-content/50">No tickets assigned to you right now.</p>
          </div>
        </div>
      <% else %>
        <!-- Ticket cards (mobile-optimized) -->
        <div class="space-y-3">
          <.ticket_card
            :for={ticket <- @tickets}
            ticket={ticket}
            expanded={@selected_ticket_id == ticket.id}
          />
        </div>
      <% end %>
    </div>
    """
  end

  # --- Ticket Card (mobile-first design) ---

  attr :ticket, Ticket, required: true
  attr :expanded, :boolean, default: false

  defp ticket_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-hidden">
      <!-- Card header — always visible -->
      <div
        class="px-4 py-3.5 cursor-pointer hover:bg-base-200/30 transition-colors"
        phx-click="toggle_ticket"
        phx-value-id={@ticket.id}
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-mono text-base-content/40">{@ticket.reference_number}</span>
              <.priority_badge priority={@ticket.priority} />
            </div>
            <p class="text-sm font-medium text-base-content leading-snug">
              {truncate(@ticket.description, 90)}
            </p>
            <div class="flex items-center gap-3 mt-2">
              <div :if={@ticket.location} class="flex items-center gap-1 text-xs text-base-content/50">
                <.icon name="hero-map-pin" class="size-3" />
                <span>{@ticket.location.name}</span>
              </div>
              <div :if={@ticket.sla_deadline} class="flex items-center gap-1 text-xs">
                <.icon name="hero-clock" class={[
                  "size-3",
                  sla_urgency_color(@ticket)
                ]} />
                <span class={sla_urgency_color(@ticket)}>
                  {sla_remaining_text(@ticket)}
                </span>
              </div>
            </div>
          </div>
          <.icon
            name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
            class="size-4 text-base-content/40 mt-1 shrink-0"
          />
        </div>
      </div>

      <!-- Expanded details -->
      <div :if={@expanded} class="border-t border-base-300">
        <!-- Full description -->
        <div class="px-4 py-3">
          <p class="text-sm text-base-content leading-relaxed">{@ticket.description}</p>
        </div>

        <!-- Attachments -->
        <div :if={@ticket.attachments != []} class="px-4 pb-3">
          <p class="text-xs font-medium text-base-content/50 mb-2">Attachments</p>
          <div class="flex gap-2">
            <div
              :for={att <- @ticket.attachments}
              class="w-16 h-16 rounded-lg bg-base-200 flex items-center justify-center"
            >
              <.icon name="hero-photo" class="size-6 text-base-content/30" />
            </div>
          </div>
        </div>

        <!-- Location map link -->
        <div :if={@ticket.location} class="px-4 pb-3">
          <a
            href={"https://www.google.com/maps/search/?api=1&query=#{URI.encode(@ticket.location.name)}"}
            target="_blank"
            class="btn btn-sm btn-outline gap-2 w-full"
          >
            <.icon name="hero-map-pin" class="size-4" />
            Navigate to Location
          </a>
        </div>

        <!-- Submitter info -->
        <div :if={@ticket.submitter_name || @ticket.submitter_phone} class="px-4 pb-3">
          <p class="text-xs font-medium text-base-content/50 mb-1">Reported by</p>
          <div class="text-sm text-base-content/70">
            <span :if={@ticket.submitter_name}>{@ticket.submitter_name}</span>
            <span :if={@ticket.submitter_phone} class="ml-2">
              <a href={"tel:#{@ticket.submitter_phone}"} class="text-primary hover:underline">
                {@ticket.submitter_phone}
              </a>
            </span>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="px-4 py-3 bg-base-200/30 flex gap-2">
          <button
            :if={@ticket.status in ["assigned", "triaged"]}
            phx-click="update_status"
            phx-value-id={@ticket.id}
            phx-value-status="in_progress"
            class="btn btn-sm btn-primary flex-1"
          >
            <.icon name="hero-play" class="size-4" />
            Start Work
          </button>

          <button
            :if={@ticket.status == "in_progress"}
            phx-click="update_status"
            phx-value-id={@ticket.id}
            phx-value-status="on_hold"
            class="btn btn-sm btn-warning btn-outline flex-1"
          >
            <.icon name="hero-pause" class="size-4" />
            On Hold
          </button>

          <button
            :if={@ticket.status == "in_progress"}
            phx-click="update_status"
            phx-value-id={@ticket.id}
            phx-value-status="completed"
            class="btn btn-sm btn-success flex-1"
          >
            <.icon name="hero-check" class="size-4" />
            Complete
          </button>

          <button
            :if={@ticket.status == "on_hold"}
            phx-click="update_status"
            phx-value-id={@ticket.id}
            phx-value-status="in_progress"
            class="btn btn-sm btn-info flex-1"
          >
            <.icon name="hero-play" class="size-4" />
            Resume
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :priority, :string, default: nil

  defp priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={[
      "badge badge-xs font-medium",
      @priority == "emergency" && "badge-error",
      @priority == "high" && "badge-warning",
      @priority == "medium" && "bg-amber-100 text-amber-700 border-amber-200",
      @priority == "low" && "badge-ghost"
    ]}>
      {String.capitalize(@priority)}
    </span>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("toggle_ticket", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_ticket_id == id, do: nil, else: id

    {:noreply, assign(socket, :selected_ticket_id, selected)}
  end

  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    ticket = Tickets.get_ticket!(id)

    # Handle SLA pause/resume
    case status do
      "on_hold" ->
        Tickets.pause_sla(ticket)
      "in_progress" when ticket.status == "on_hold" ->
        Tickets.resume_sla(ticket)
      _ ->
        :ok
    end

    {:ok, _} = Tickets.update_ticket(ticket, %{status: status})

    # Log the status change
    Tickets.log_activity(id, "status_change", "Status changed to #{status}", %{
      from: ticket.status,
      to: status
    })

    # Reload
    tickets = Tickets.list_user_tickets(socket.assigns.user.id)
    {:noreply, assign(socket, :tickets, tickets)}
  end

  # --- Helpers ---

  defp sla_remaining_text(%{sla_deadline: nil}), do: "No deadline"
  defp sla_remaining_text(%{sla_deadline: _deadline, sla_paused_at: paused_at}) when not is_nil(paused_at) do
    "Paused"
  end
  defp sla_remaining_text(%{sla_deadline: deadline}) do
    now = DateTime.utc_now()
    diff = DateTime.diff(deadline, now, :minute)

    cond do
      diff < 0 -> "#{abs(diff)} min overdue"
      diff < 60 -> "#{diff} min left"
      diff < 1440 -> "#{div(diff, 60)}h left"
      true -> "#{div(diff, 1440)}d left"
    end
  end

  defp sla_urgency_color(%{sla_deadline: nil}), do: "text-base-content/40"
  defp sla_urgency_color(%{sla_breached: true}), do: "text-error"
  defp sla_urgency_color(%{sla_deadline: deadline}) do
    now = DateTime.utc_now()
    diff = DateTime.diff(deadline, now, :minute)

    cond do
      diff < 0 -> "text-error"
      diff < 60 -> "text-error"
      diff < 240 -> "text-warning"
      true -> "text-base-content/50"
    end
  end

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."
end
