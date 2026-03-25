defmodule FixlyWeb.Admin.TicketListLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.Ticket
  alias Fixly.Accounts
  alias Fixly.Organizations

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    tickets = if org_id, do: Tickets.list_tickets(org_id), else: []
    grouped = group_by_status(tickets)
    counts = compute_counts(tickets)

    internal_users = if org_id, do: Accounts.list_users_by_organization(org_id), else: []
    contractor_orgs = if org_id, do: Organizations.list_contractor_orgs(org_id), else: []

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
      |> assign(:comments, [])
      |> assign(:comment_body, "")
      |> assign(:org_id, org_id)
      |> assign(:internal_users, internal_users)
      |> assign(:contractor_orgs, contractor_orgs)
      |> assign(:current_user, user)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex gap-6 h-full">
      <!-- Main content (shrinks when panel is open) -->
      <div class={["flex-1 min-w-0 space-y-6 transition-all duration-300", @selected_ticket && "lg:mr-0"]}>
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
              <div class="join">
                <button phx-click="set_view_mode" phx-value-mode="list" class={["join-item btn btn-sm", @view_mode == "list" && "btn-active"]}>
                  <.icon name="hero-bars-3" class="size-4" /> List
                </button>
                <button phx-click="set_view_mode" phx-value-mode="kanban" class={["join-item btn btn-sm", @view_mode == "kanban" && "btn-active"]}>
                  <.icon name="hero-view-columns" class="size-4" /> Kanban
                </button>
              </div>
              <div class="divider divider-horizontal mx-1 h-6"></div>
              <!-- Status filter -->
              <div class="dropdown">
                <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1.5">
                  <.icon name="hero-funnel" class="size-4" /> Filter
                </div>
                <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-44 p-2 shadow-lg border border-base-300">
                  <li :for={{val, label} <- [{"all", "All Statuses"}, {"created", "Open"}, {"assigned", "Assigned"}, {"in_progress", "In Progress"}, {"on_hold", "On Hold"}, {"completed", "Completed"}]}>
                    <a phx-click="set_filter_status" phx-value-status={val} class={@filter_status == val && "active"}>{label}</a>
                  </li>
                </ul>
              </div>
              <!-- Priority filter -->
              <div class="dropdown">
                <div tabindex="0" role="button" class="btn btn-sm btn-ghost gap-1.5">
                  <.icon name="hero-flag" class="size-4" /> Priority
                </div>
                <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-10 w-40 p-2 shadow-lg border border-base-300">
                  <li :for={{val, label} <- [{"all", "All"}, {"emergency", "Emergency"}, {"high", "High"}, {"medium", "Medium"}, {"low", "Low"}]}>
                    <a phx-click="set_filter_priority" phx-value-priority={val} class={@filter_priority == val && "active"}>{label}</a>
                  </li>
                </ul>
              </div>
            </div>
            <div class="relative hidden sm:block">
              <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
              <input type="text" placeholder="Search tickets..." class="input input-sm input-bordered pl-9 w-56" />
            </div>
          </div>

          <!-- List view -->
          <div :if={@view_mode == "list"}>
            <%= if @tickets == [] do %>
              <.empty_state />
            <% else %>
              <.ticket_table_grouped grouped={@grouped} selected_id={@selected_ticket && @selected_ticket.id} />
            <% end %>
          </div>

          <!-- Kanban view -->
          <div :if={@view_mode == "kanban"} class="p-5">
            <%= if @tickets == [] do %>
              <.empty_state />
            <% else %>
              <.kanban_board grouped={@grouped} selected_id={@selected_ticket && @selected_ticket.id} />
            <% end %>
          </div>
        </div>
      </div>

      <!-- Slide-over panel -->
      <.ticket_panel
        :if={@selected_ticket}
        ticket={@selected_ticket}
        comments={@comments}
        comment_body={@comment_body}
        internal_users={@internal_users}
        contractor_orgs={@contractor_orgs}
      />
    </div>
    """
  end

  # ==========================================
  # SLIDE-OVER PANEL
  # ==========================================

  defp ticket_panel(assigns) do
    ~H"""
    <div class="w-full lg:w-[420px] shrink-0 bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-y-auto max-h-[calc(100vh-7rem)] animate-in slide-in-from-right">
      <!-- Panel header -->
      <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-5 py-3.5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <span class="text-base font-bold text-base-content">{@ticket.reference_number}</span>
            <.status_badge status={@ticket.status} />
          </div>
          <div class="flex items-center gap-1">
            <.link navigate={~p"/admin/tickets/#{@ticket.id}"} class="btn btn-ghost btn-xs btn-square" title="Open full page">
              <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
            </.link>
            <button phx-click="close_panel" class="btn btn-ghost btn-xs btn-square">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- Panel body -->
      <div class="p-5 space-y-5">
        <!-- Quick info rows -->
        <div class="space-y-3">
          <.info_row label="Status">
            <.status_badge status={@ticket.status} />
          </.info_row>

          <.info_row label="Priority">
            <.priority_badge priority={@ticket.priority} />
          </.info_row>

          <.info_row :if={@ticket.location} label="Location">
            <div class="flex items-center gap-1.5 text-sm text-base-content">
              <.icon name="hero-map-pin" class="size-3.5 text-base-content/40" />
              <span>{location_breadcrumb(@ticket.location)}</span>
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

          <.info_row :if={@ticket.assigned_to_user} label="Assigned to">
            <div class="flex items-center gap-2">
              <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center">
                <span class="text-[10px] font-semibold text-primary">
                  {String.first(@ticket.assigned_to_user.name || @ticket.assigned_to_user.email) |> String.upcase()}
                </span>
              </div>
              <span class="text-sm text-base-content">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
            </div>
          </.info_row>

          <.info_row :if={@ticket.sla_deadline} label="SLA Deadline">
            <span class={["text-sm font-medium", sla_color(@ticket)]}>
              {sla_text(@ticket)}
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

        <!-- Priority selector -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Set Priority</p>
          <div class="grid grid-cols-4 gap-1.5">
            <button
              :for={{p, label, color} <- [{"emergency", "Urgent", "btn-error"}, {"high", "High", "btn-warning"}, {"medium", "Medium", "btn-ghost border-amber-300"}, {"low", "Low", "btn-ghost"}]}
              phx-click="set_priority"
              phx-value-priority={p}
              class={["btn btn-xs", @ticket.priority == p && color, @ticket.priority != p && "btn-ghost opacity-60"]}
            >
              {label}
            </button>
          </div>
        </div>

        <!-- Assignment -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Assignment</p>
          <div class="space-y-2">
            <select class="select select-bordered select-sm w-full" phx-change="assign_to_org" name="org_id">
              <option value="">— Assign to contractor —</option>
              <option :for={org <- @contractor_orgs} value={org.id} selected={@ticket.assigned_to_org_id == org.id}>
                {org.name}
              </option>
            </select>
            <select class="select select-bordered select-sm w-full" phx-change="assign_to_user" name="user_id">
              <option value="">— Assign to technician —</option>
              <option :for={user <- @internal_users} value={user.id} selected={@ticket.assigned_to_user_id == user.id}>
                {user.name || user.email}
              </option>
            </select>
          </div>
        </div>

        <!-- Status actions -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Actions</p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={{s, label, icon} <- status_actions(@ticket.status)}
              phx-click="update_status"
              phx-value-status={s}
              class="btn btn-sm btn-outline gap-1.5"
            >
              <.icon name={icon} class="size-3.5" />
              {label}
            </button>
          </div>
        </div>

        <!-- Navigate to location -->
        <a
          :if={@ticket.location}
          href={"https://www.google.com/maps/search/?api=1&query=#{URI.encode(@ticket.location.name)}"}
          target="_blank"
          class="btn btn-sm btn-outline w-full gap-2"
        >
          <.icon name="hero-map-pin" class="size-4" />
          Navigate to Location
        </a>

        <!-- Comments / Discussion -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider">
              Discussion
              <span :if={@comments != []} class="ml-1 badge badge-xs badge-ghost">{length(@comments)}</span>
            </p>
          </div>

          <div class="space-y-3 mb-3 max-h-64 overflow-y-auto">
            <div :for={comment <- @comments} class="flex gap-2.5">
              <div class="w-7 h-7 rounded-full bg-base-200 flex items-center justify-center shrink-0 mt-0.5">
                <span class="text-[10px] font-semibold text-base-content/50">
                  {comment_initials(comment)}
                </span>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-0.5">
                  <span class="text-xs font-semibold text-base-content">{comment_author(comment)}</span>
                  <span class="text-[10px] text-base-content/40">{Calendar.strftime(comment.inserted_at, "%b %d %I:%M %p")}</span>
                </div>
                <p class="text-sm text-base-content/70 leading-relaxed">{comment.body}</p>
              </div>
            </div>
            <p :if={@comments == []} class="text-xs text-base-content/40 text-center py-3">No comments yet</p>
          </div>

          <form phx-submit="add_comment" class="flex gap-2">
            <input
              type="text"
              name="body"
              value={@comment_body}
              placeholder="Add a comment..."
              class="input input-sm input-bordered flex-1"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-sm btn-primary">
              <.icon name="hero-paper-airplane" class="size-3.5" />
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # Info row for the panel
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp info_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4">
      <span class="text-xs text-base-content/50 shrink-0 w-24">{@label}</span>
      <div class="flex-1 text-right">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ==========================================
  # STAT CARD
  # ==========================================

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
        <div class={["w-11 h-11 rounded-xl flex items-center justify-center", "bg-#{@color}/10"]}>
          <.icon name={@icon} class={["size-5", "text-#{@color}"]} />
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # GROUPED TABLE
  # ==========================================

  attr :grouped, :list, required: true
  attr :selected_id, :string, default: nil

  defp ticket_table_grouped(assigns) do
    ~H"""
    <div>
      <.ticket_group
        :for={{status, tickets} <- @grouped}
        :if={tickets != []}
        status={status}
        tickets={tickets}
        selected_id={@selected_id}
      />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :selected_id, :string, default: nil

  defp ticket_group(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 px-5 py-2.5 bg-base-200/50 border-b border-base-300">
        <div class={["w-1 h-4 rounded-full", status_bar_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">{status_label(@status)}</span>
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
      </div>
      <div class="grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
        <span>Ticket</span><span>Location</span><span>Category</span><span>Priority</span><span>Assigned To</span><span>Date</span>
      </div>
      <.ticket_row :for={ticket <- @tickets} ticket={ticket} selected={@selected_id == ticket.id} />
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :selected, :boolean, default: false

  defp ticket_row(assigns) do
    ~H"""
    <div
      phx-click="select_ticket"
      phx-value-id={@ticket.id}
      class={[
        "grid grid-cols-[3fr_2fr_1fr_1fr_1.5fr_1fr] gap-4 px-5 py-3.5 border-b border-base-200 items-center cursor-pointer transition-colors",
        @selected && "bg-primary/5 border-l-2 border-l-primary",
        !@selected && "hover:bg-base-200/30"
      ]}
    >
      <div class="min-w-0">
        <p class="text-sm font-medium text-base-content truncate">{truncate(@ticket.description, 60)}</p>
        <p class="text-xs text-base-content/50 mt-0.5">
          {@ticket.reference_number}
          <span :if={@ticket.submitter_name}> · {@ticket.submitter_name}</span>
        </p>
      </div>
      <div class="min-w-0">
        <p :if={@ticket.location} class="text-sm text-base-content/70 truncate">{@ticket.location.name}</p>
        <p :if={!@ticket.location} class="text-sm text-base-content/30">—</p>
      </div>
      <div>
        <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
        <span :if={!@ticket.category} class="text-sm text-base-content/30">—</span>
      </div>
      <div><.priority_badge priority={@ticket.priority} /></div>
      <div class="min-w-0">
        <span :if={@ticket.assigned_to_user} class="text-sm text-base-content/70 truncate">{@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}</span>
        <span :if={!@ticket.assigned_to_user && @ticket.assigned_to_org} class="text-sm text-base-content/50 truncate">{@ticket.assigned_to_org.name}</span>
        <span :if={!@ticket.assigned_to_user && !@ticket.assigned_to_org} class="text-xs text-base-content/30">Unassigned</span>
      </div>
      <div><p class="text-sm text-base-content/60">{format_date(@ticket.inserted_at)}</p></div>
    </div>
    """
  end

  # ==========================================
  # KANBAN BOARD
  # ==========================================

  attr :grouped, :list, required: true
  attr :selected_id, :string, default: nil

  defp kanban_board(assigns) do
    ~H"""
    <div class="flex gap-4 overflow-x-auto pb-4">
      <.kanban_column :for={{status, tickets} <- @grouped} status={status} tickets={tickets} selected_id={@selected_id} />
    </div>
    """
  end

  attr :status, :string, required: true
  attr :tickets, :list, required: true
  attr :selected_id, :string, default: nil

  defp kanban_column(assigns) do
    ~H"""
    <div class="flex-shrink-0 w-72">
      <div class="flex items-center gap-2 mb-3">
        <div class={["w-2 h-2 rounded-full", status_dot_color(@status)]}></div>
        <span class="text-sm font-semibold text-base-content">{status_label(@status)}</span>
        <span class="badge badge-sm badge-ghost">{length(@tickets)}</span>
      </div>
      <div class="space-y-2.5">
        <.kanban_card :for={ticket <- @tickets} ticket={ticket} selected={@selected_id == ticket.id} />
      </div>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :selected, :boolean, default: false

  defp kanban_card(assigns) do
    ~H"""
    <div
      phx-click="select_ticket"
      phx-value-id={@ticket.id}
      class={[
        "rounded-lg border p-3.5 shadow-sm cursor-pointer transition-all",
        @selected && "border-primary bg-primary/5 shadow-md ring-1 ring-primary/20",
        !@selected && "border-base-300 bg-base-100 hover:shadow-md"
      ]}
    >
      <div class="flex items-start justify-between gap-2 mb-2">
        <div class="flex flex-wrap gap-1.5">
          <.priority_badge :if={@ticket.priority} priority={@ticket.priority} />
          <span :if={@ticket.category} class="badge badge-sm badge-ghost">{@ticket.category}</span>
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
        </div>
        <span :if={!@ticket.assigned_to_user} class="text-[10px] text-base-content/30">Unassigned</span>
        <span class="text-xs text-base-content/40">{format_date(@ticket.inserted_at)}</span>
      </div>
    </div>
    """
  end

  # ==========================================
  # SHARED COMPONENTS
  # ==========================================

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-20 text-center">
      <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
        <.icon name="hero-ticket" class="size-7 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content mb-1">No tickets yet</h3>
      <p class="text-sm text-base-content/50 max-w-xs">Tickets will appear here when residents scan a QR code and submit a maintenance request.</p>
    </div>
    """
  end

  attr :status, :string, required: true
  defp status_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm font-medium", status_badge_class(@status)]}>{status_label(@status)}</span>
    """
  end

  attr :priority, :string, default: nil
  defp priority_badge(assigns) do
    ~H"""
    <span :if={@priority} class={["badge badge-sm font-medium", priority_badge_class(@priority)]}>
      <span class={["w-1.5 h-1.5 rounded-full mr-1.5", priority_dot_class(@priority)]}></span>
      {String.capitalize(@priority)}
    </span>
    <span :if={!@priority} class="text-xs text-base-content/30">—</span>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true
  def handle_event("select_ticket", %{"id" => id}, socket) do
    # If clicking the same ticket, close the panel
    if socket.assigns.selected_ticket && socket.assigns.selected_ticket.id == id do
      {:noreply, assign(socket, selected_ticket: nil, comments: [])}
    else
      ticket = Tickets.get_ticket!(id)
      comments = Tickets.list_comments(id)
      {:noreply, assign(socket, selected_ticket: ticket, comments: comments, comment_body: "")}
    end
  end

  def handle_event("close_panel", _, socket) do
    {:noreply, assign(socket, selected_ticket: nil, comments: [])}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  def handle_event("set_filter_status", %{"status" => status}, socket) do
    tickets =
      if socket.assigns.org_id do
        if status == "all", do: Tickets.list_tickets(socket.assigns.org_id), else: Tickets.list_tickets(socket.assigns.org_id, status: status)
      else
        []
      end

    {:noreply, socket |> assign(filter_status: status, tickets: tickets, grouped: group_by_status(tickets), selected_ticket: nil, comments: [])}
  end

  def handle_event("set_filter_priority", %{"priority" => priority}, socket) do
    tickets =
      if socket.assigns.org_id do
        if priority == "all", do: Tickets.list_tickets(socket.assigns.org_id), else: Tickets.list_tickets(socket.assigns.org_id, priority: priority)
      else
        []
      end

    {:noreply, socket |> assign(filter_priority: priority, tickets: tickets, grouped: group_by_status(tickets), selected_ticket: nil, comments: [])}
  end

  def handle_event("set_priority", %{"priority" => priority}, socket) do
    {:ok, ticket} = Tickets.set_priority(socket.assigns.selected_ticket, priority)
    ticket = Tickets.get_ticket!(ticket.id)
    Tickets.log_activity(ticket.id, "system", "Priority set to #{priority}")
    {:noreply, socket |> assign(selected_ticket: ticket) |> reload_tickets()}
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    ticket = socket.assigns.selected_ticket

    case status do
      "on_hold" -> Tickets.pause_sla(ticket)
      "in_progress" when ticket.status == "on_hold" -> Tickets.resume_sla(ticket)
      _ -> :ok
    end

    {:ok, _} = Tickets.update_ticket(ticket, %{status: status})
    Tickets.log_activity(ticket.id, "status_change", "Status changed to #{status_label(status)}", %{from: ticket.status, to: status})
    updated = Tickets.get_ticket!(ticket.id)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("assign_to_org", %{"org_id" => ""}, socket) do
    {:ok, _} = Tickets.update_ticket(socket.assigns.selected_ticket, %{assigned_to_org_id: nil})
    updated = Tickets.get_ticket!(socket.assigns.selected_ticket.id)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("assign_to_org", %{"org_id" => org_id}, socket) do
    {:ok, _} = Tickets.assign_ticket(socket.assigns.selected_ticket, %{assigned_to_org_id: org_id})
    Tickets.log_activity(socket.assigns.selected_ticket.id, "assignment", "Assigned to contractor")
    updated = Tickets.get_ticket!(socket.assigns.selected_ticket.id)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("assign_to_user", %{"user_id" => ""}, socket) do
    {:ok, _} = Tickets.update_ticket(socket.assigns.selected_ticket, %{assigned_to_user_id: nil})
    updated = Tickets.get_ticket!(socket.assigns.selected_ticket.id)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("assign_to_user", %{"user_id" => user_id}, socket) do
    {:ok, _} = Tickets.assign_ticket(socket.assigns.selected_ticket, %{assigned_to_user_id: user_id})
    Tickets.log_activity(socket.assigns.selected_ticket.id, "assignment", "Assigned to technician")
    updated = Tickets.get_ticket!(socket.assigns.selected_ticket.id)
    {:noreply, socket |> assign(selected_ticket: updated) |> reload_tickets()}
  end

  def handle_event("add_comment", %{"body" => body}, socket) when byte_size(body) > 0 do
    user = socket.assigns.current_user

    {:ok, _} = Tickets.create_comment(%{
      ticket_id: socket.assigns.selected_ticket.id,
      user_id: user.id,
      body: body
    })

    comments = Tickets.list_comments(socket.assigns.selected_ticket.id)
    {:noreply, assign(socket, comments: comments, comment_body: "")}
  end

  def handle_event("add_comment", _, socket), do: {:noreply, socket}

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload_tickets(socket) do
    tickets = if socket.assigns.org_id, do: Tickets.list_tickets(socket.assigns.org_id), else: []
    assign(socket, tickets: tickets, grouped: group_by_status(tickets), counts: compute_counts(tickets))
  end

  defp compute_counts(tickets) do
    %{
      total: length(tickets),
      open: length(Enum.filter(tickets, &(&1.status in ["created", "triaged"]))),
      in_progress: length(Enum.filter(tickets, &(&1.status in ["assigned", "in_progress"]))),
      on_hold: length(Enum.filter(tickets, &(&1.status == "on_hold"))),
      completed: length(Enum.filter(tickets, &(&1.status in ["completed", "reviewed", "closed"])))
    }
  end

  defp group_by_status(tickets) do
    order = ["created", "triaged", "assigned", "in_progress", "on_hold", "completed", "reviewed", "closed"]
    grouped = Enum.group_by(tickets, & &1.status)
    order |> Enum.map(fn s -> {s, Map.get(grouped, s, [])} end) |> Enum.reject(fn {_, t} -> t == [] end)
  end

  defp status_actions("created"), do: [{"triaged", "Triage", "hero-clipboard-document-check"}, {"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("triaged"), do: [{"assigned", "Assign", "hero-user-plus"}]
  defp status_actions("assigned"), do: [{"in_progress", "Start Work", "hero-play"}, {"on_hold", "Hold", "hero-pause"}]
  defp status_actions("in_progress"), do: [{"on_hold", "Hold", "hero-pause"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("on_hold"), do: [{"in_progress", "Resume", "hero-play"}, {"completed", "Complete", "hero-check"}]
  defp status_actions("completed"), do: [{"reviewed", "Review", "hero-eye"}, {"closed", "Close", "hero-x-circle"}]
  defp status_actions("reviewed"), do: [{"closed", "Close", "hero-x-circle"}]
  defp status_actions(_), do: []

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(other)

  defp status_badge_class("created"), do: "badge-success badge-outline"
  defp status_badge_class("triaged"), do: "badge-info badge-outline"
  defp status_badge_class("assigned"), do: "badge-primary badge-outline"
  defp status_badge_class("in_progress"), do: "badge-info"
  defp status_badge_class("on_hold"), do: "badge-warning"
  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_bar_color("created"), do: "bg-success"
  defp status_bar_color("triaged"), do: "bg-info"
  defp status_bar_color("assigned"), do: "bg-primary"
  defp status_bar_color("in_progress"), do: "bg-info"
  defp status_bar_color("on_hold"), do: "bg-warning"
  defp status_bar_color("completed"), do: "bg-success"
  defp status_bar_color(_), do: "bg-base-content/30"

  defp status_dot_color("created"), do: "bg-success"
  defp status_dot_color("triaged"), do: "bg-info"
  defp status_dot_color("assigned"), do: "bg-primary"
  defp status_dot_color("in_progress"), do: "bg-info"
  defp status_dot_color("on_hold"), do: "bg-warning"
  defp status_dot_color("completed"), do: "bg-success"
  defp status_dot_color(_), do: "bg-base-content/30"

  defp priority_badge_class("emergency"), do: "badge-error"
  defp priority_badge_class("high"), do: "badge-warning"
  defp priority_badge_class("medium"), do: "bg-amber-100 text-amber-700 border-amber-200"
  defp priority_badge_class(_), do: "badge-ghost"

  defp priority_dot_class("emergency"), do: "bg-error-content"
  defp priority_dot_class("high"), do: "bg-warning-content"
  defp priority_dot_class("medium"), do: "bg-amber-500"
  defp priority_dot_class(_), do: "bg-base-content/40"

  defp sla_text(%{sla_deadline: nil}), do: "No deadline"
  defp sla_text(%{sla_paused_at: p}) when not is_nil(p), do: "Paused"
  defp sla_text(%{sla_deadline: deadline}) do
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
    cond do
      diff < 0 -> "#{abs(diff)} min overdue"
      diff < 60 -> "#{diff} min left"
      diff < 1440 -> "#{div(diff, 60)}h #{rem(diff, 60)}m left"
      true -> "#{div(diff, 1440)}d left"
    end
  end

  defp sla_color(%{sla_breached: true}), do: "text-error"
  defp sla_color(%{sla_deadline: nil}), do: "text-base-content/50"
  defp sla_color(%{sla_paused_at: p}) when not is_nil(p), do: "text-warning"
  defp sla_color(%{sla_deadline: deadline}) do
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
    cond do
      diff < 0 -> "text-error"
      diff < 120 -> "text-error"
      diff < 480 -> "text-warning"
      true -> "text-success"
    end
  end

  defp location_breadcrumb(location) do
    build_ancestor_names(location, []) |> Enum.join(" > ")
  end

  defp build_ancestor_names(nil, acc), do: acc
  defp build_ancestor_names(location, acc) do
    location = Fixly.Repo.preload(location, :parent)
    case location.parent do
      nil -> [location.name | acc]
      parent -> build_ancestor_names(parent, [location.name | acc])
    end
  end

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(_), do: "System"

  defp comment_initials(%{user: %{name: name}}) when is_binary(name) and name != "" do
    name |> String.split(" ") |> Enum.take(2) |> Enum.map(&String.first/1) |> Enum.join() |> String.upcase()
  end
  defp comment_initials(%{user: %{email: email}}) when is_binary(email), do: email |> String.first() |> String.upcase()
  defp comment_initials(_), do: "S"

  defp format_date(nil), do: ""
  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d")

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."
end
