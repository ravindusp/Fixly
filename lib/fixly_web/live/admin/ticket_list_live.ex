defmodule FixlyWeb.Admin.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    tickets =
      if org_id do
        Tickets.list_tickets(org_id)
      else
        []
      end

    # Group tickets by status for the list view
    grouped = group_by_status(tickets)

    # Counts
    counts = %{
      total: length(tickets),
      open: length(Enum.filter(tickets, &(&1.status in ["created", "triaged"]))),
      in_progress: length(Enum.filter(tickets, &(&1.status in ["assigned", "in_progress"]))),
      on_hold: length(Enum.filter(tickets, &(&1.status == "on_hold"))),
      completed: length(Enum.filter(tickets, &(&1.status in ["completed", "reviewed", "closed"])))
    }

    socket =
      socket
      |> assign(:page_title, "Tickets")
      |> assign(:tickets, tickets)
      |> assign(:grouped, grouped)
      |> assign(:counts, counts)
      |> assign(:view_mode, "list")
      |> assign(:filter_status, "all")
      |> assign(:filter_priority, "all")
      |> assign(:selected_ticket, nil)
      |> assign(:org_id, org_id)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats cards -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Total Tickets" value={@counts.total} icon="hero-ticket" color="primary" />
        <.stat_card label="Open" value={@counts.open} icon="hero-inbox" color="success" />
        <.stat_card label="In Progress" value={@counts.in_progress} icon="hero-arrow-path" color="info" />
        <.stat_card label="On Hold" value={@counts.on_hold} icon="hero-pause-circle" color="warning" />
      </div>

      <!-- Toolbar -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="flex items-center justify-between px-5 py-3.5 border-b border-base-300">
          <div class="flex items-center gap-2">
            <!-- View mode toggles -->
            <div class="join">
              <button
                phx-click="set_view_mode"
                phx-value-mode="list"
                class={["join-item btn btn-sm", @view_mode == "list" && "btn-active"]}
              >
                <.icon name="hero-bars-3" class="size-4" />
                List
              </button>
              <button
                phx-click="set_view_mode"
                phx-value-mode="kanban"
                class={["join-item btn btn-sm", @view_mode == "kanban" && "btn-active"]}
              >
                <.icon name="hero-view-columns" class="size-4" />
                Kanban
              </button>
            </div>

            <div class="divider divider-horizontal mx-1 h-6"></div>

            <!-- Status filter -->
            <div class="dropdown">
              <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1.5">
                <.icon name="hero-funnel" class="size-4" />
                Filter
              </div>
              <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-44 p-2 shadow-lg border border-base-300">
                <li><a phx-click="set_filter_status" phx-value-status="all" class={@filter_status == "all" && "active"}>All Statuses</a></li>
                <li><a phx-click="set_filter_status" phx-value-status="created" class={@filter_status == "created" && "active"}>Open</a></li>
                <li><a phx-click="set_filter_status" phx-value-status="assigned" class={@filter_status == "assigned" && "active"}>Assigned</a></li>
                <li><a phx-click="set_filter_status" phx-value-status="in_progress" class={@filter_status == "in_progress" && "active"}>In Progress</a></li>
                <li><a phx-click="set_filter_status" phx-value-status="on_hold" class={@filter_status == "on_hold" && "active"}>On Hold</a></li>
                <li><a phx-click="set_filter_status" phx-value-status="completed" class={@filter_status == "completed" && "active"}>Completed</a></li>
              </ul>
            </div>

            <!-- Priority filter -->
            <div class="dropdown">
              <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1.5">
                <.icon name="hero-flag" class="size-4" />
                Priority
              </div>
              <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-40 p-2 shadow-lg border border-base-300">
                <li><a phx-click="set_filter_priority" phx-value-priority="all" class={@filter_priority == "all" && "active"}>All</a></li>
                <li><a phx-click="set_filter_priority" phx-value-priority="emergency" class={@filter_priority == "emergency" && "active"}>Emergency</a></li>
                <li><a phx-click="set_filter_priority" phx-value-priority="high" class={@filter_priority == "high" && "active"}>High</a></li>
                <li><a phx-click="set_filter_priority" phx-value-priority="medium" class={@filter_priority == "medium" && "active"}>Medium</a></li>
                <li><a phx-click="set_filter_priority" phx-value-priority="low" class={@filter_priority == "low" && "active"}>Low</a></li>
              </ul>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <div class="relative">
              <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
              <input
                type="text"
                placeholder="Search tickets..."
                class="input input-sm input-bordered pl-9 w-56"
              />
            </div>
          </div>
        </div>

        <!-- List view -->
        <div :if={@view_mode == "list"}>
          <%= if @tickets == [] do %>
            <.empty_state />
          <% else %>
            <.ticket_table_grouped grouped={@grouped} />
          <% end %>
        </div>

        <!-- Kanban view -->
        <div :if={@view_mode == "kanban"} class="p-5">
          <%= if @tickets == [] do %>
            <.empty_state />
          <% else %>
            <.kanban_board grouped={@grouped} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # --- Stat Card ---

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

  # --- Grouped Table ---

  attr :grouped, :map, required: true

  defp ticket_table_grouped(assigns) do
    ~H"""
    <div>
      <.ticket_group
        :for={{status, tickets} <- @grouped}
        :if={tickets != []}
        status={status}
        tickets={tickets}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true

  defp ticket_group(assigns) do
    ~H"""
    <div>
      <!-- Group header -->
      <div class="flex items-center gap-2 px-5 py-2.5 bg-base-200/50 border-b border-base-300">
        <div class={["w-1 h-4 rounded-full", status_bar_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">
          {status_label(@status)}
        </span>
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
      </div>

      <!-- Table header -->
      <div class="grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
        <span>Ticket</span>
        <span>Location</span>
        <span>Category</span>
        <span>Priority</span>
        <span>Assigned To</span>
        <span>Date</span>
      </div>

      <!-- Rows -->
      <.ticket_row :for={ticket <- @tickets} ticket={ticket} />
    </div>
    """
  end

  attr :ticket, Ticket, required: true

  defp ticket_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center hover:bg-base-200/30 cursor-pointer transition-colors">
      <!-- Ticket info -->
      <div class="flex items-center gap-3 min-w-0">
        <div>
          <p class="text-sm font-medium text-base-content truncate">
            {truncate(@ticket.description, 60)}
          </p>
          <p class="text-xs text-base-content/50 mt-0.5">
            {@ticket.reference_number}
            <span :if={@ticket.submitter_name}> &middot; {@ticket.submitter_name}</span>
          </p>
        </div>
      </div>

      <!-- Location -->
      <div class="min-w-0">
        <p :if={@ticket.location} class="text-sm text-base-content/70 truncate">
          {@ticket.location.name}
        </p>
        <p :if={@ticket.custom_location_name} class="text-sm text-base-content/50 italic truncate">
          {@ticket.custom_location_name}
        </p>
        <p :if={!@ticket.location && !@ticket.custom_location_name} class="text-sm text-base-content/30">
          —
        </p>
      </div>

      <!-- Category -->
      <div>
        <span :if={@ticket.category} class="badge badge-sm badge-ghost">
          {@ticket.category}
        </span>
        <span :if={!@ticket.category} class="text-sm text-base-content/30">—</span>
      </div>

      <!-- Priority -->
      <div>
        <.priority_badge priority={@ticket.priority} />
      </div>

      <!-- Assigned to -->
      <div class="min-w-0">
        <div :if={@ticket.assigned_to_user} class="flex items-center gap-2">
          <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center">
            <span class="text-[10px] font-semibold text-primary">
              {String.first(@ticket.assigned_to_user.name || @ticket.assigned_to_user.email) |> String.upcase()}
            </span>
          </div>
          <span class="text-sm text-base-content/70 truncate">
            {@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}
          </span>
        </div>
        <div :if={@ticket.assigned_to_org && !@ticket.assigned_to_user} class="text-sm text-base-content/50 truncate">
          {@ticket.assigned_to_org.name}
        </div>
        <span :if={!@ticket.assigned_to_user && !@ticket.assigned_to_org} class="text-xs text-base-content/30">
          Unassigned
        </span>
      </div>

      <!-- Date -->
      <div>
        <p class="text-sm text-base-content/60">{format_date(@ticket.inserted_at)}</p>
      </div>
    </div>
    """
  end

  # --- Kanban Board ---

  attr :grouped, :map, required: true

  defp kanban_board(assigns) do
    ~H"""
    <div class="flex gap-4 overflow-x-auto pb-4">
      <.kanban_column
        :for={{status, tickets} <- @grouped}
        status={status}
        tickets={tickets}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true

  defp kanban_column(assigns) do
    ~H"""
    <div class="flex-shrink-0 w-72">
      <!-- Column header -->
      <div class="flex items-center gap-2 mb-3">
        <div class={["w-2 h-2 rounded-full", status_dot_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">{status_label(@status)}</span>
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
        <button class="ml-auto btn btn-ghost btn-xs btn-square">
          <.icon name="hero-plus" class="size-3.5" />
        </button>
      </div>

      <!-- Cards -->
      <div class="space-y-2.5">
        <.kanban_card :for={ticket <- @tickets} ticket={ticket} />
      </div>
    </div>
    """
  end

  attr :ticket, Ticket, required: true

  defp kanban_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 p-3.5 shadow-sm hover:shadow-md transition-shadow cursor-pointer">
      <div class="flex items-start justify-between gap-2 mb-2">
        <div class="flex flex-wrap gap-1.5">
          <.priority_badge :if={@ticket.priority} priority={@ticket.priority} />
          <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
        </div>
        <span class="text-xs text-base-content/40 font-mono shrink-0">{@ticket.reference_number}</span>
      </div>

      <p class="text-sm font-medium text-base-content leading-snug mb-2">
        {truncate(@ticket.description, 80)}
      </p>

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

  # --- Empty State ---

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
        <.icon name="hero-ticket" class="size-7 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content mb-1">No tickets yet</h3>
      <p class="text-sm text-base-content/50 max-w-xs">
        Tickets will appear here when residents scan a QR code and submit a maintenance request.
      </p>
    </div>
    """
  end

  # --- Priority Badge ---

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
      <span class={[
        "w-1.5 h-1.5 rounded-full mr-1.5",
        @priority == "emergency" && "bg-error-content",
        @priority == "high" && "bg-warning-content",
        @priority == "medium" && "bg-amber-500",
        @priority == "low" && "bg-base-content/40"
      ]}></span>
      {String.capitalize(@priority || "")}
    </span>
    <span :if={!@priority} class="text-xs text-base-content/30">—</span>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  def handle_event("set_filter_status", %{"status" => status}, socket) do
    tickets =
      if socket.assigns.org_id do
        if status == "all" do
          Tickets.list_tickets(socket.assigns.org_id)
        else
          Tickets.list_tickets(socket.assigns.org_id, status: status)
        end
      else
        []
      end

    {:noreply,
     socket
     |> assign(:filter_status, status)
     |> assign(:tickets, tickets)
     |> assign(:grouped, group_by_status(tickets))}
  end

  def handle_event("set_filter_priority", %{"priority" => priority}, socket) do
    tickets =
      if socket.assigns.org_id do
        if priority == "all" do
          Tickets.list_tickets(socket.assigns.org_id)
        else
          Tickets.list_tickets(socket.assigns.org_id, priority: priority)
        end
      else
        []
      end

    {:noreply,
     socket
     |> assign(:filter_priority, priority)
     |> assign(:tickets, tickets)
     |> assign(:grouped, group_by_status(tickets))}
  end

  # --- Helpers ---

  defp group_by_status(tickets) do
    order = ["created", "triaged", "assigned", "in_progress", "on_hold", "completed", "reviewed", "closed"]

    grouped = Enum.group_by(tickets, & &1.status)

    order
    |> Enum.map(fn status -> {status, Map.get(grouped, status, [])} end)
    |> Enum.reject(fn {_status, tickets} -> tickets == [] end)
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

  defp status_bar_color("created"), do: "bg-success"
  defp status_bar_color("triaged"), do: "bg-info"
  defp status_bar_color("assigned"), do: "bg-primary"
  defp status_bar_color("in_progress"), do: "bg-info"
  defp status_bar_color("on_hold"), do: "bg-warning"
  defp status_bar_color("completed"), do: "bg-success"
  defp status_bar_color("reviewed"), do: "bg-success"
  defp status_bar_color("closed"), do: "bg-base-content/30"
  defp status_bar_color(_), do: "bg-base-content/20"

  defp status_dot_color("created"), do: "bg-success"
  defp status_dot_color("triaged"), do: "bg-info"
  defp status_dot_color("assigned"), do: "bg-primary"
  defp status_dot_color("in_progress"), do: "bg-info"
  defp status_dot_color("on_hold"), do: "bg-warning"
  defp status_dot_color("completed"), do: "bg-success"
  defp status_dot_color(_), do: "bg-base-content/30"

  defp format_date(nil), do: ""
  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."
end
