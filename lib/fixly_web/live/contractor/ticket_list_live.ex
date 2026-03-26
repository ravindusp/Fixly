defmodule FixlyWeb.Contractor.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    technicians = if org_id, do: Accounts.list_technicians_by_organization(org_id), else: []

    socket =
      socket
      |> assign(:page_title, "Assigned Tickets")
      |> assign(:technicians, technicians)
      |> assign(:org_id, org_id)
      |> assign(:selected_ticket, nil)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Assigned" value={@counts.total} icon="hero-inbox-stack" color="primary" />
        <.stat_card label="Open" value={@counts.open} icon="hero-inbox" color="success" />
        <.stat_card label="In Progress" value={@counts.in_progress} icon="hero-arrow-path" color="info" />
        <.stat_card label="On Hold" value={@counts.on_hold} icon="hero-pause-circle" color="warning" />
      </div>

      <!-- Ticket list -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="flex items-center justify-between px-5 py-3.5 border-b border-base-300">
          <h2 class="text-sm font-semibold text-base-content">Tickets Assigned to Your Team</h2>
        </div>

        <!-- Table header -->
        <div class="grid grid-cols-[2.5fr_1.5fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
          <span>Ticket</span>
          <span>Location</span>
          <span>Priority</span>
          <span>Status</span>
          <span>Assigned To</span>
          <span></span>
        </div>

        <!-- Rows (streamed) -->
        <div id="contractor-tickets-stream" phx-update="stream">
          <div
            :for={{dom_id, ticket} <- @streams.tickets}
            id={dom_id}
            class="grid grid-cols-[2.5fr_1.5fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center hover:bg-base-200/30 transition-colors"
          >
            <div class="min-w-0">
              <p class="text-sm font-medium text-base-content truncate">{truncate(ticket.description, 55)}</p>
              <p class="text-xs text-base-content/50 mt-0.5">{ticket.reference_number}</p>
            </div>

            <div class="min-w-0">
              <p :if={ticket.location} class="text-sm text-base-content/70 truncate">{ticket.location.name}</p>
              <p :if={!ticket.location} class="text-sm text-base-content/30">—</p>
            </div>

            <div>
              <.priority_badge priority={ticket.priority} />
            </div>

            <div>
              <.status_badge status={ticket.status} />
            </div>

            <div>
              <%= if ticket.assigned_to_user do %>
                <span class="text-sm text-base-content/70">{ticket.assigned_to_user.name || ticket.assigned_to_user.email}</span>
              <% else %>
                <div class="dropdown dropdown-end">
                  <div tabindex="0" role="button" class="btn btn-xs btn-outline btn-primary">Assign</div>
                  <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-48 p-2 shadow-lg border border-base-300">
                    <li :for={tech <- @technicians}>
                      <a phx-click="assign_technician" phx-value-ticket-id={ticket.id} phx-value-user-id={tech.id}>
                        {tech.name || tech.email}
                      </a>
                    </li>
                    <li :if={@technicians == []}>
                      <span class="text-base-content/50">No technicians available</span>
                    </li>
                  </ul>
                </div>
              <% end %>
            </div>

            <div class="text-right">
              <.link navigate={~p"/contractor/tickets/#{ticket.id}"} class="btn btn-xs btn-ghost">
                View
              </.link>
            </div>
          </div>
        </div>

        <!-- Empty state -->
        <div :if={@counts.total == 0} class="flex flex-col items-center justify-center py-16 text-center">
          <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
            <.icon name="hero-inbox" class="size-6 text-base-content/30" />
          </div>
          <h3 class="text-base font-semibold text-base-content mb-1">No tickets assigned yet</h3>
          <p class="text-sm text-base-content/50">Tickets will appear here when the school admin assigns work to your team.</p>
        </div>

        <!-- Infinite scroll sentinel -->
        <div
          :if={@has_more}
          id="contractor-tickets-scroll"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          class="flex justify-center py-4"
        >
          <span class="loading loading-spinner loading-sm text-base-content/30"></span>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

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
        <div class={[
          "w-11 h-11 rounded-xl flex items-center justify-center",
          @color == "primary" && "bg-primary/10",
          @color == "success" && "bg-success/10",
          @color == "info" && "bg-info/10",
          @color == "warning" && "bg-warning/10"
        ]}>
          <.icon name={@icon} class={[
            "size-5",
            @color == "primary" && "text-primary",
            @color == "success" && "text-success",
            @color == "info" && "text-info",
            @color == "warning" && "text-warning"
          ]} />
        </div>
      </div>
    </div>
    """
  end

  attr :priority, :string, default: nil

  defp priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={[
      "badge badge-sm font-medium",
      @priority == "emergency" && "badge-error",
      @priority == "high" && "badge-warning",
      @priority == "medium" && "bg-amber-100 text-amber-700 border-amber-200",
      @priority == "low" && "badge-ghost"
    ]}>
      {String.capitalize(@priority)}
    </span>
    <span :if={!@priority} class="text-xs text-base-content/30">—</span>
    """
  end

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @status in ["created", "triaged"] && "badge-success badge-outline",
      @status == "assigned" && "badge-primary badge-outline",
      @status == "in_progress" && "badge-info",
      @status == "on_hold" && "badge-warning",
      @status in ["completed", "reviewed", "closed"] && "badge-ghost"
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      page = Tickets.list_contractor_tickets_paginated(socket.assigns.org_id, socket.assigns.cursor)

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:tickets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("assign_technician", %{"ticket-id" => ticket_id, "user-id" => user_id}, socket) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = socket.assigns.current_scope.user

    case Tickets.assign_to_technician(ticket, user_id, user) do
      {:ok, _ticket} ->
        {:noreply, reload_data(socket)}

      {:error, :not_your_ticket} ->
        {:noreply, put_flash(socket, :error, "This ticket is not assigned to your organization")}

      {:error, :tech_not_in_org} ->
        {:noreply, put_flash(socket, :error, "This technician is not in your organization")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to assign technician")}
    end
  end

  # --- Helpers ---

  defp reload_data(socket) do
    org_id = socket.assigns.org_id

    if org_id do
      status_counts = Tickets.count_contractor_tickets_by_status(org_id)
      counts = %{
        total: status_counts |> Map.values() |> Enum.sum(),
        open: Map.get(status_counts, "created", 0) + Map.get(status_counts, "triaged", 0) + Map.get(status_counts, "assigned", 0),
        in_progress: Map.get(status_counts, "in_progress", 0),
        on_hold: Map.get(status_counts, "on_hold", 0),
        completed: Map.get(status_counts, "completed", 0) + Map.get(status_counts, "reviewed", 0) + Map.get(status_counts, "closed", 0)
      }

      page = Tickets.list_contractor_tickets_paginated(org_id)

      socket
      |> assign(:counts, counts)
      |> assign(:cursor, page.cursor)
      |> assign(:has_more, page.has_more)
      |> stream(:tickets, page.entries, reset: true)
    else
      socket
      |> assign(:counts, %{total: 0, open: 0, in_progress: 0, on_hold: 0, completed: 0})
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> stream(:tickets, [], reset: true)
    end
  end

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(other)

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."
end
