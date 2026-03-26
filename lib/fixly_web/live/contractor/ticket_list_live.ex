defmodule FixlyWeb.Contractor.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Accounts
  alias Fixly.PubSubBroadcast

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    if connected?(socket) && org_id do
      PubSubBroadcast.subscribe_contractor(org_id)
    end

    technicians = if org_id, do: Accounts.list_technicians_by_organization(org_id), else: []

    socket =
      socket
      |> assign(:page_title, "Assigned Tickets")
      |> assign(:technicians, technicians)
      |> assign(:org_id, org_id)
      |> assign(:current_user, user)
      |> assign(:view_mode, "list")
      |> assign(:selected_ticket, nil)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:grouped, [])
      |> assign(:kanban_loading, MapSet.new())
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:ticket_updated, _ticket}, socket) do
    socket =
      if socket.assigns.selected_ticket do
        assign(socket, :selected_ticket, Tickets.get_ticket!(socket.assigns.selected_ticket.id))
      else
        socket
      end

    {:noreply, reload_data(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex gap-6 h-full">
      <!-- Main content -->
      <div class="flex-1 min-w-0 space-y-6">
        <!-- Stats -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <.stat_card label="Assigned" value={@counts.total} icon="hero-inbox-stack" color="primary" />
          <.stat_card label="Open" value={@counts.open} icon="hero-inbox" color="success" />
          <.stat_card label="In Progress" value={@counts.in_progress} icon="hero-arrow-path" color="info" />
          <.stat_card label="On Hold" value={@counts.on_hold} icon="hero-pause-circle" color="warning" />
        </div>

        <!-- Ticket list / kanban -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="flex items-center justify-between px-5 py-3.5 border-b border-base-300">
            <h2 class="text-sm font-semibold text-base-content">Tickets Assigned to Your Team</h2>
            <div class="flex items-center gap-1 bg-base-200 rounded-lg p-0.5">
              <button
                phx-click="set_view_mode"
                phx-value-mode="list"
                class={["btn btn-xs gap-1.5", @view_mode == "list" && "btn-active", @view_mode != "list" && "btn-ghost"]}
              >
                <.icon name="hero-list-bullet" class="size-3.5" />
                List
              </button>
              <button
                phx-click="set_view_mode"
                phx-value-mode="kanban"
                class={["btn btn-xs gap-1.5", @view_mode == "kanban" && "btn-active", @view_mode != "kanban" && "btn-ghost"]}
              >
                <.icon name="hero-view-columns" class="size-3.5" />
                Kanban
              </button>
            </div>
          </div>

          <!-- List view -->
          <div :if={@view_mode == "list"}>
            <div class="grid grid-cols-[2.5fr_1.5fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
              <span>Ticket</span>
              <span>Location</span>
              <span>Priority</span>
              <span>Status</span>
              <span>Assigned To</span>
              <span></span>
            </div>

            <div id="contractor-tickets-stream" phx-update="stream">
              <div
                :for={{dom_id, ticket} <- @streams.tickets}
                id={dom_id}
                phx-click="select_ticket"
                phx-value-id={ticket.id}
                class={[
                  "grid grid-cols-[2.5fr_1.5fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center cursor-pointer transition-colors",
                  @selected_ticket && @selected_ticket.id == ticket.id && "bg-primary/5",
                  "hover:bg-base-200/30"
                ]}
              >
                <div class="min-w-0">
                  <p class="text-sm font-medium text-base-content truncate">{truncate(ticket.description, 55)}</p>
                  <p class="text-xs text-base-content/50 mt-0.5">{ticket.reference_number}</p>
                </div>
                <div class="min-w-0">
                  <p :if={ticket.location} class="text-sm text-base-content/70 truncate">{ticket.location.name}</p>
                  <p :if={!ticket.location} class="text-sm text-base-content/30">—</p>
                </div>
                <div><.priority_badge priority={ticket.priority} /></div>
                <div><.status_badge status={ticket.status} /></div>
                <div>
                  <%= if ticket.assigned_to_user do %>
                    <span class="text-sm text-base-content/70">{ticket.assigned_to_user.name || ticket.assigned_to_user.email}</span>
                  <% else %>
                    <span class="text-xs text-base-content/40">Unassigned</span>
                  <% end %>
                </div>
                <div class="text-right">
                  <.link navigate={~p"/contractor/tickets/#{ticket.id}"} class="btn btn-xs btn-ghost">
                    View
                  </.link>
                </div>
              </div>
            </div>

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

          <!-- Kanban view -->
          <div :if={@view_mode == "kanban"} class="p-5">
            <.kanban_board
              grouped={@grouped}
              kanban_loading={@kanban_loading}
              selected_id={@selected_ticket && @selected_ticket.id}
            />
          </div>

          <div :if={@counts.total == 0 && @view_mode == "list"} class="flex flex-col items-center justify-center py-16 text-center">
            <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
              <.icon name="hero-inbox" class="size-6 text-base-content/30" />
            </div>
            <h3 class="text-base font-semibold text-base-content mb-1">No tickets assigned yet</h3>
            <p class="text-sm text-base-content/50">Tickets will appear here when the property manager assigns work to your team.</p>
          </div>
        </div>
      </div>

      <!-- Side panel -->
      <.ticket_panel
        :if={@selected_ticket}
        ticket={@selected_ticket}
        technicians={@technicians}
      />
    </div>
    """
  end

  # --- Side Panel ---

  attr :ticket, :map, required: true
  attr :technicians, :list, required: true

  defp ticket_panel(assigns) do
    ~H"""
    <div class="w-full lg:w-[400px] shrink-0 bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-y-auto max-h-[calc(100vh-7rem)] animate-in slide-in-from-right">
      <!-- Header -->
      <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-5 py-3.5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <span class="text-base font-bold text-base-content">{@ticket.reference_number}</span>
            <.status_badge status={@ticket.status} />
          </div>
          <div class="flex items-center gap-1">
            <.link navigate={~p"/contractor/tickets/#{@ticket.id}"} class="btn btn-ghost btn-xs btn-square" title="Open full page">
              <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
            </.link>
            <button phx-click="close_panel" class="btn btn-ghost btn-xs btn-square">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- Body -->
      <div class="p-5 space-y-5">
        <!-- Info rows -->
        <div class="space-y-3">
          <.info_row label="Priority">
            <.priority_badge priority={@ticket.priority} />
          </.info_row>

          <.info_row :if={@ticket.location} label="Location">
            <div class="flex items-center gap-1.5 text-sm text-base-content">
              <.icon name="hero-map-pin" class="size-3.5 text-base-content/40" />
              <span>{@ticket.location.name}</span>
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

          <.info_row label="Technician">
            <%= if @ticket.assigned_to_user do %>
              <div class="flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center">
                  <span class="text-[10px] font-semibold text-primary">
                    {String.first(@ticket.assigned_to_user.name || @ticket.assigned_to_user.email) |> String.upcase()}
                  </span>
                </div>
                <span class="text-sm text-base-content">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
              </div>
            <% else %>
              <span class="text-sm text-base-content/40">Unassigned</span>
            <% end %>
          </.info_row>

          <.info_row :if={@ticket.sla_deadline} label="SLA Deadline">
            <span class="text-sm font-medium text-base-content/70">
              {Calendar.strftime(@ticket.sla_deadline, "%b %d, %Y at %I:%M %p")}
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

        <!-- Technician assignment -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Assign Technician</p>
          <form phx-change="panel_assign_technician">
            <select name="user_id" class="select select-sm select-bordered w-full">
              <option value="">— Select technician —</option>
              <option
                :for={tech <- @technicians}
                value={tech.id}
                selected={@ticket.assigned_to_user_id == tech.id}
              >
                {tech.name || tech.email}
              </option>
            </select>
          </form>
        </div>

        <!-- Status actions -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Actions</p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={{s, label, icon} <- contractor_status_actions(@ticket.status)}
              phx-click="update_status"
              phx-value-status={s}
              class="btn btn-sm btn-outline gap-1.5"
            >
              <.icon name={icon} class="size-3.5" />
              {label}
            </button>
          </div>
        </div>

        <!-- Navigate -->
        <a
          :if={@ticket.location}
          href={maps_url(@ticket)}
          target="_blank"
          class="btn btn-sm btn-outline w-full gap-2"
        >
          <.icon name="hero-map-pin" class="size-4" />
          Navigate to Location
        </a>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp info_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-xs text-base-content/50">{@label}</span>
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  # --- Kanban Components ---

  attr :grouped, :list, required: true
  attr :kanban_loading, :any, required: true
  attr :selected_id, :string, default: nil

  defp kanban_board(assigns) do
    ~H"""
    <div class="flex gap-4 overflow-x-auto pb-4 items-stretch min-h-[400px]">
      <.kanban_column
        :for={{status, group_data} <- @grouped}
        status={status}
        tickets={group_data.tickets}
        total={group_data.total}
        has_more={group_data.has_more}
        loading={MapSet.member?(@kanban_loading, status)}
        selected_id={@selected_id}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :total, :integer, required: true
  attr :has_more, :boolean, required: true
  attr :loading, :boolean, default: false
  attr :selected_id, :string, default: nil

  defp kanban_column(assigns) do
    assigns = assign(assigns, :indexed_tickets, Enum.with_index(assigns.tickets, 1))

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
        <span class="badge badge-sm badge-ghost">{@total}</span>
      </div>
      <div class="space-y-2.5 flex-1 min-h-[200px] max-h-[calc(100vh-16rem)] overflow-y-auto kanban-dropzone rounded-lg transition-colors p-1" id={"kanban-scroll-#{@status}"}>
        <.kanban_card
          :for={{ticket, idx} <- @indexed_tickets}
          ticket={ticket}
          index={idx}
          selected={@selected_id == ticket.id}
        />
        <div :if={@loading} class="flex justify-center py-3">
          <span class="loading loading-spinner loading-sm text-primary"></span>
        </div>
      </div>
    </div>
    """
  end

  attr :ticket, :map, required: true
  attr :index, :integer, required: true
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
        <div class="flex items-center gap-1.5">
          <span class="text-[10px] font-mono text-base-content/25 w-5 shrink-0">{@index}</span>
          <div class="flex flex-wrap gap-1.5">
            <.priority_badge :if={@ticket.priority} priority={@ticket.priority} />
            <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
          </div>
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
          <span class="text-xs text-base-content/50">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
        </div>
        <span :if={!@ticket.assigned_to_user} class="text-[10px] text-base-content/30">Unassigned</span>
        <span class="text-xs text-base-content/40">{format_date(@ticket.inserted_at)}</span>
      </div>
    </div>
    """
  end

  # --- Shared Components ---

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
  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, socket |> assign(:view_mode, mode) |> reload_data()}
  end

  def handle_event("select_ticket", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    {:noreply, assign(socket, :selected_ticket, ticket)}
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, assign(socket, :selected_ticket, nil)}
  end

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

  def handle_event("update_status", %{"status" => new_status}, socket) do
    ticket = socket.assigns.selected_ticket
    user = socket.assigns.current_user

    case Tickets.update_ticket_status(ticket, new_status, user) do
      {:ok, _} ->
        Tickets.log_ticket_event(ticket.id, "status_change", "Status changed from #{status_label(ticket.status)} to #{status_label(new_status)}", %{from: ticket.status, to: new_status, changed_by: user.name || user.email})
        updated = Tickets.get_ticket!(ticket.id)
        {:noreply, socket |> assign(:selected_ticket, updated) |> reload_data()}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot change status from #{status_label(ticket.status)} to #{status_label(new_status)}")}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Proof of completion required before marking as completed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("kanban_drop", %{"ticket_id" => ticket_id, "new_status" => new_status}, socket) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = socket.assigns.current_user

    if ticket.status == new_status do
      {:noreply, socket}
    else
      case Tickets.update_ticket_status(ticket, new_status, user) do
        {:ok, _} ->
          Tickets.log_ticket_event(ticket.id, "status_change", "Status changed from #{status_label(ticket.status)} to #{status_label(new_status)}", %{from: ticket.status, to: new_status, changed_by: user.name || user.email})

          socket =
            if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == ticket_id do
              assign(socket, :selected_ticket, Tickets.get_ticket!(ticket_id))
            else
              socket
            end

          {:noreply, reload_data(socket)}

        {:error, :unauthorized_transition} ->
          {:noreply, put_flash(socket, :error, "Cannot move ticket from #{status_label(ticket.status)} to #{status_label(new_status)}")}

        {:error, :proof_required} ->
          {:noreply, put_flash(socket, :error, "Proof of completion required before marking as completed")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to update status")}
      end
    end
  end

  def handle_event("panel_assign_technician", %{"user_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("panel_assign_technician", %{"user_id" => user_id}, socket) do
    ticket = socket.assigns.selected_ticket
    user = socket.assigns.current_scope.user

    case Tickets.assign_to_technician(ticket, user_id, user) do
      {:ok, _} ->
        updated = Tickets.get_ticket!(ticket.id)
        {:noreply, socket |> assign(:selected_ticket, updated) |> reload_data()}

      {:error, :not_your_ticket} ->
        {:noreply, put_flash(socket, :error, "This ticket is not assigned to your organization")}

      {:error, :tech_not_in_org} ->
        {:noreply, put_flash(socket, :error, "This technician is not in your organization")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to assign technician")}
    end
  end

  def handle_event("assign_technician", %{"ticket-id" => ticket_id, "user-id" => user_id}, socket) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = socket.assigns.current_scope.user

    case Tickets.assign_to_technician(ticket, user_id, user) do
      {:ok, _ticket} ->
        {:noreply, reload_data(socket)}

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

      grouped = Tickets.list_contractor_tickets_by_status(org_id, 20)
      socket = assign(socket, :counts, counts) |> assign(:grouped, grouped)

      case socket.assigns.view_mode do
        "kanban" ->
          socket
          |> stream(:tickets, [], reset: true)
          |> assign(:cursor, nil)
          |> assign(:has_more, false)

        _ ->
          page = Tickets.list_contractor_tickets_paginated(org_id)
          socket
          |> assign(:cursor, page.cursor)
          |> assign(:has_more, page.has_more)
          |> stream(:tickets, page.entries, reset: true)
      end
    else
      empty_grouped =
        ~w(assigned in_progress on_hold completed)
        |> Enum.map(fn s -> {s, %{tickets: [], total: 0, has_more: false}} end)

      socket
      |> assign(:counts, %{total: 0, open: 0, in_progress: 0, on_hold: 0, completed: 0})
      |> assign(:grouped, empty_grouped)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> stream(:tickets, [], reset: true)
    end
  end

  defp contractor_status_actions("assigned"), do: [{"in_progress", "Start Work", "hero-play"}]
  defp contractor_status_actions("in_progress"), do: [{"on_hold", "Pause", "hero-pause"}, {"completed", "Complete", "hero-check"}]
  defp contractor_status_actions("on_hold"), do: [{"in_progress", "Resume", "hero-play"}]
  defp contractor_status_actions(_), do: []

  defp maps_url(ticket) do
    cond do
      ticket.location && ticket.location.metadata["gps_lat"] && ticket.location.metadata["gps_lng"] ->
        lat = ticket.location.metadata["gps_lat"]
        lng = ticket.location.metadata["gps_lng"]
        "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}"

      ticket.location ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.location.name)}"

      true ->
        "#"
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

  defp status_dot_color("assigned"), do: "bg-primary"
  defp status_dot_color("in_progress"), do: "bg-info"
  defp status_dot_color("on_hold"), do: "bg-warning"
  defp status_dot_color("completed"), do: "bg-success"
  defp status_dot_color(_), do: "bg-gray-400"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."
end
