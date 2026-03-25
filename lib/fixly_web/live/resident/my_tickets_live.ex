defmodule FixlyWeb.Resident.MyTicketsLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:page_title, "My Tickets")
      |> assign(:user, user)
      |> assign(:expanded_id, nil)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:ticket_count, 0)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-base-content">My Tickets</h1>
          <p class="text-sm text-base-content/50 mt-1">
            {@ticket_count} {if @ticket_count == 1, do: "ticket", else: "tickets"} submitted
          </p>
        </div>
        <.link navigate={~p"/"} class="btn btn-sm btn-primary gap-1.5">
          <.icon name="hero-plus" class="size-4" />
          Report Another Issue
        </.link>
      </div>

      <!-- Ticket List (streamed) -->
      <div id="resident-tickets-stream" phx-update="stream">
        <.resident_ticket_card
          :for={{dom_id, ticket} <- @streams.tickets}
          id={dom_id}
          ticket={ticket}
          expanded={@expanded_id == ticket.id}
        />
      </div>

      <!-- Empty state -->
      <div :if={@ticket_count == 0} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="flex flex-col items-center justify-center py-20 text-center px-6">
          <div class="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mb-4">
            <.icon name="hero-ticket" class="size-8 text-primary" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">No tickets yet</h3>
          <p class="text-sm text-base-content/50 max-w-md mb-4">
            You haven't submitted any maintenance requests yet. Scan a QR code at your location or use the button above to report an issue.
          </p>
          <.link navigate={~p"/"} class="btn btn-primary gap-1.5">
            <.icon name="hero-plus" class="size-4" />
            Report an Issue
          </.link>
        </div>
      </div>

      <!-- Infinite scroll sentinel -->
      <div
        :if={@has_more}
        id="resident-tickets-scroll"
        phx-hook="InfiniteScroll"
        data-has-more={to_string(@has_more)}
        class="flex justify-center py-4"
      >
        <span class="loading loading-spinner loading-sm text-base-content/30"></span>
      </div>
    </div>
    """
  end

  # ==========================================
  # TICKET CARD (expandable)
  # ==========================================

  attr :id, :string, required: true
  attr :ticket, Ticket, required: true
  attr :expanded, :boolean, default: false

  defp resident_ticket_card(assigns) do
    ~H"""
    <div id={@id} class="bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-hidden mb-3">
      <!-- Card header (always visible, click to expand) -->
      <div
        class="px-5 py-4 cursor-pointer hover:bg-base-200/30 transition-colors"
        phx-click="toggle_ticket"
        phx-value-id={@ticket.id}
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-1.5">
              <span class="text-xs font-mono text-base-content/40">{@ticket.reference_number}</span>
              <.resident_status_badge status={@ticket.status} />
              <.resident_priority_badge :if={@ticket.priority} priority={@ticket.priority} />
            </div>
            <p class="text-sm font-medium text-base-content leading-snug line-clamp-2">
              {@ticket.description}
            </p>
            <div class="flex items-center gap-3 mt-2 text-xs text-base-content/50">
              <span :if={@ticket.location}>
                <.icon name="hero-map-pin" class="size-3 inline" />
                {@ticket.location.name}
              </span>
              <span :if={@ticket.category} class="capitalize">
                <.icon name="hero-tag" class="size-3 inline" />
                {@ticket.category}
              </span>
              <span>
                <.icon name="hero-calendar" class="size-3 inline" />
                {Calendar.strftime(@ticket.inserted_at, "%b %d, %Y")}
              </span>
            </div>
          </div>
          <div class="shrink-0 mt-1">
            <.icon
              name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="size-5 text-base-content/30"
            />
          </div>
        </div>
      </div>

      <!-- Expanded detail panel -->
      <div :if={@expanded} class="px-5 pb-5 border-t border-base-200">
        <div class="pt-4 space-y-4">
          <!-- Full description -->
          <div>
            <h4 class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-1">Description</h4>
            <p class="text-sm text-base-content whitespace-pre-wrap">{@ticket.description}</p>
          </div>

          <!-- Details grid -->
          <div class="grid grid-cols-2 gap-3">
            <div :if={@ticket.location} class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Location</p>
              <p class="text-sm font-medium text-base-content">{@ticket.location.name}</p>
            </div>
            <div :if={@ticket.custom_location_name} class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Specific Location</p>
              <p class="text-sm font-medium text-base-content">{@ticket.custom_location_name}</p>
            </div>
            <div :if={@ticket.custom_item_name} class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Item</p>
              <p class="text-sm font-medium text-base-content">{@ticket.custom_item_name}</p>
            </div>
            <div :if={@ticket.category} class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Category</p>
              <p class="text-sm font-medium text-base-content capitalize">{@ticket.category}</p>
            </div>
            <div class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Submitted</p>
              <p class="text-sm font-medium text-base-content">{Calendar.strftime(@ticket.inserted_at, "%b %d, %Y at %H:%M")}</p>
            </div>
            <div :if={@ticket.priority} class="bg-base-200/50 rounded-lg p-3">
              <p class="text-xs text-base-content/50 mb-0.5">Priority</p>
              <p class="text-sm font-medium text-base-content capitalize">{@ticket.priority}</p>
            </div>
          </div>

          <!-- Status Timeline -->
          <div>
            <h4 class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-3">Status Timeline</h4>
            <.status_timeline status={@ticket.status} inserted_at={@ticket.inserted_at} />
          </div>

          <!-- Attachments -->
          <div :if={@ticket.attachments != [] && @ticket.attachments != nil}>
            <h4 class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-2">Attachments</h4>
            <div class="flex gap-2 flex-wrap">
              <%= for attachment <- (@ticket.attachments || []) do %>
                <div class="badge badge-ghost badge-sm gap-1">
                  <.icon name="hero-paper-clip" class="size-3" />
                  {attachment.file_name || "File"}
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # SUB-COMPONENTS
  # ==========================================

  attr :status, :string, required: true

  defp resident_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      @status in ["created", "triaged"] && "badge-info",
      @status in ["assigned", "in_progress"] && "badge-primary",
      @status == "on_hold" && "badge-warning",
      @status in ["completed", "reviewed"] && "badge-success",
      @status == "closed" && "badge-ghost"
    ]}>
      {format_status(@status)}
    </span>
    """
  end

  attr :priority, :string, required: true

  defp resident_priority_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm badge-outline",
      @priority == "emergency" && "badge-error",
      @priority == "high" && "badge-warning",
      @priority == "medium" && "badge-info",
      @priority == "low" && "badge-ghost"
    ]}>
      {@priority}
    </span>
    """
  end

  attr :status, :string, required: true
  attr :inserted_at, :any, required: true

  defp status_timeline(assigns) do
    steps = [
      {"created", "Submitted", "hero-paper-airplane"},
      {"triaged", "Under Review", "hero-eye"},
      {"assigned", "Assigned", "hero-user-plus"},
      {"in_progress", "In Progress", "hero-wrench-screwdriver"},
      {"completed", "Completed", "hero-check-circle"},
      {"closed", "Closed", "hero-archive-box"}
    ]

    current_idx = Enum.find_index(steps, fn {s, _, _} -> s == assigns.status end) || 0
    current_idx =
      case assigns.status do
        "on_hold" -> 3
        "reviewed" -> 4
        _ -> current_idx
      end

    assigns = assign(assigns, steps: steps, current_idx: current_idx)

    ~H"""
    <div class="flex items-center gap-0">
      <%= for {step, idx} <- Enum.with_index(@steps) do %>
        <% {_key, label, icon} = step %>
        <% is_done = idx <= @current_idx %>
        <% is_current = idx == @current_idx %>

        <!-- Step -->
        <div class="flex flex-col items-center flex-1 min-w-0">
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center mb-1",
            is_current && "bg-primary text-primary-content",
            is_done && !is_current && "bg-primary/20 text-primary",
            !is_done && "bg-base-200 text-base-content/30"
          ]}>
            <.icon name={icon} class="size-4" />
          </div>
          <span class={[
            "text-[10px] font-medium text-center leading-tight",
            is_done && "text-base-content",
            !is_done && "text-base-content/30"
          ]}>
            {label}
          </span>
        </div>

        <!-- Connector line -->
        <div :if={idx < length(@steps) - 1} class={[
          "h-0.5 flex-1 -mt-4",
          idx < @current_idx && "bg-primary/30",
          idx >= @current_idx && "bg-base-200"
        ]}>
        </div>
      <% end %>
    </div>

    <!-- Special state indicator -->
    <div :if={@status == "on_hold"} class="mt-3 flex items-center gap-2 p-2 rounded-lg bg-warning/10 border border-warning/20">
      <.icon name="hero-pause-circle" class="size-4 text-warning" />
      <span class="text-sm text-warning">Ticket is currently on hold</span>
    </div>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true
  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      user = socket.assigns.user
      page = Tickets.list_resident_tickets_paginated(user.id, user.email, socket.assigns.cursor)

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:tickets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_ticket", %{"id" => id}, socket) do
    expanded_id =
      if socket.assigns.expanded_id == id do
        nil
      else
        id
      end

    {:noreply, assign(socket, :expanded_id, expanded_id)}
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload_data(socket) do
    user = socket.assigns.user
    count = Tickets.count_resident_tickets(user.id, user.email)
    page = Tickets.list_resident_tickets_paginated(user.id, user.email)

    socket
    |> assign(:ticket_count, count)
    |> assign(:cursor, page.cursor)
    |> assign(:has_more, page.has_more)
    |> stream(:tickets, page.entries, reset: true)
  end

  defp format_status("created"), do: "Submitted"
  defp format_status("triaged"), do: "Under Review"
  defp format_status("assigned"), do: "Assigned"
  defp format_status("in_progress"), do: "In Progress"
  defp format_status("on_hold"), do: "On Hold"
  defp format_status("completed"), do: "Completed"
  defp format_status("reviewed"), do: "Reviewed"
  defp format_status("closed"), do: "Closed"
  defp format_status(other), do: other
end
