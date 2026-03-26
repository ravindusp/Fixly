defmodule FixlyWeb.Admin.TicketDetailLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.{Ticket, StatusMachine}
  alias Fixly.Organizations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id
    ticket = Tickets.get_ticket_for_org!(org_id, id)
    comments = Tickets.list_comments(id)

    contractor_orgs =
      if org_id, do: Organizations.list_contractor_orgs(org_id), else: []

    socket =
      socket
      |> assign(:page_title, ticket.reference_number)
      |> assign(:ticket, ticket)
      |> assign(:comments, comments)
      |> assign(:contractor_orgs, contractor_orgs)
      |> assign(:current_user, user)
      |> assign(:comment_body, "")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Back link + header -->
      <div class="flex items-center gap-3">
        <.link navigate={~p"/admin/tickets"} class="btn btn-ghost btn-sm gap-1.5">
          <.icon name="hero-arrow-left" class="size-4" />
          Back to Tickets
        </.link>
      </div>

      <!-- Page header -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-base-content">{@ticket.reference_number}</h1>
          <.status_badge status={@ticket.status} />
          <.priority_pill priority={@ticket.priority} />
        </div>
        <div class="flex items-center gap-2">
          <button
            :if={@ticket.status != "on_hold"}
            phx-click="toggle_on_hold"
            class="btn btn-sm btn-outline btn-warning gap-1.5"
          >
            <.icon name="hero-pause-circle" class="size-4" />
            Put On Hold
          </button>
          <button
            :if={@ticket.status == "on_hold"}
            phx-click="toggle_on_hold"
            class="btn btn-sm btn-outline btn-info gap-1.5"
          >
            <.icon name="hero-play-circle" class="size-4" />
            Resume
          </button>
        </div>
      </div>

      <!-- Two-column layout -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Left column — Ticket Info (2/3 width) -->
        <div class="lg:col-span-2 space-y-6">
          <.ticket_info_card ticket={@ticket} />
          <.attachments_card ticket={@ticket} />
          <.submitter_card ticket={@ticket} />
          <.location_card ticket={@ticket} />
          <.comments_card
            comments={@comments}
            comment_body={@comment_body}
          />
        </div>

        <!-- Right column — Actions & Controls (1/3 width) -->
        <div class="space-y-6">
          <.priority_selector ticket={@ticket} />
          <.status_controls ticket={@ticket} />
          <.assignment_section
            ticket={@ticket}
            contractor_orgs={@contractor_orgs}
          />
          <.sla_card ticket={@ticket} />
        </div>
      </div>
    </div>
    """
  end

  # =============================================
  # Left Column Components
  # =============================================

  defp ticket_info_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content">Ticket Details</h2>
      </div>
      <div class="p-6 space-y-4">
        <!-- Location breadcrumb -->
        <div :if={@ticket.location || @ticket.custom_location_name} class="flex items-center gap-2 text-sm">
          <.icon name="hero-map-pin" class="size-4 text-base-content/50" />
          <span class="text-base-content/70">
            <span :if={@ticket.location}>
              {location_breadcrumb(@ticket.location)}
            </span>
            <span :if={!@ticket.location && @ticket.custom_location_name} class="italic">
              {@ticket.custom_location_name}
            </span>
          </span>
        </div>

        <!-- Category -->
        <div :if={@ticket.category} class="flex items-center gap-2 text-sm">
          <.icon name="hero-tag" class="size-4 text-base-content/50" />
          <span class="badge badge-sm badge-ghost">{String.capitalize(@ticket.category)}</span>
        </div>

        <!-- Description -->
        <div>
          <label class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Description</label>
          <p class="mt-1.5 text-sm text-base-content leading-relaxed whitespace-pre-wrap">{@ticket.description}</p>
        </div>

        <!-- Submitted date -->
        <div class="flex items-center gap-2 text-xs text-base-content/50 pt-2 border-t border-base-200">
          <.icon name="hero-clock" class="size-3.5" />
          Submitted {format_datetime(@ticket.inserted_at)}
        </div>
      </div>
    </div>
    """
  end

  defp attachments_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-paper-clip" class="size-4" />
          Attachments
          <span class="badge badge-sm badge-ghost">{length(@ticket.attachments)}</span>
        </h2>
      </div>
      <div class="p-6">
        <%= if @ticket.attachments == [] do %>
          <div class="text-center py-6">
            <div class="w-12 h-12 rounded-xl bg-base-200 flex items-center justify-center mx-auto mb-3">
              <.icon name="hero-paper-clip" class="size-5 text-base-content/30" />
            </div>
            <p class="text-sm text-base-content/40">No attachments</p>
          </div>
        <% else %>
          <div class="space-y-2">
            <div
              :for={attachment <- @ticket.attachments}
              class="flex items-center gap-3 p-3 rounded-lg bg-base-200/50 border border-base-200"
            >
              <div class="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                <.icon name={file_icon(attachment.file_type)} class="size-4 text-primary" />
              </div>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-base-content truncate">{attachment.file_name || "Untitled"}</p>
                <p :if={attachment.file_size} class="text-xs text-base-content/50">{format_file_size(attachment.file_size)}</p>
              </div>
              <a
                :if={attachment.file_url}
                href={attachment.file_url}
                target="_blank"
                rel="noopener"
                class="btn btn-ghost btn-xs btn-square"
              >
                <.icon name="hero-arrow-down-tray" class="size-3.5" />
              </a>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp submitter_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-user" class="size-4" />
          Submitter Info
        </h2>
      </div>
      <div class="p-6">
        <div class="flex items-start gap-4">
          <div class="w-11 h-11 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
            <span class="text-sm font-semibold text-primary">
              {submitter_initial(@ticket)}
            </span>
          </div>
          <div class="space-y-1.5 min-w-0">
            <p :if={@ticket.submitter_name} class="text-sm font-medium text-base-content">
              {@ticket.submitter_name}
            </p>
            <p :if={!@ticket.submitter_name} class="text-sm text-base-content/40 italic">
              Anonymous
            </p>
            <div :if={@ticket.submitter_email} class="flex items-center gap-1.5 text-sm text-base-content/60">
              <.icon name="hero-envelope" class="size-3.5" />
              <a href={"mailto:#{@ticket.submitter_email}"} class="hover:text-primary transition-colors">
                {@ticket.submitter_email}
              </a>
            </div>
            <div :if={@ticket.submitter_phone} class="flex items-center gap-1.5 text-sm text-base-content/60">
              <.icon name="hero-phone" class="size-3.5" />
              <a href={"tel:#{@ticket.submitter_phone}"} class="hover:text-primary transition-colors">
                {@ticket.submitter_phone}
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp location_card(assigns) do
    ~H"""
    <div :if={@ticket.location || @ticket.custom_location_name} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-map-pin" class="size-4" />
          Location
        </h2>
      </div>
      <div class="p-6">
        <div class="flex items-center justify-between gap-3">
          <div>
            <p class="text-sm font-medium text-base-content">
              {location_display_name(@ticket)}
            </p>
            <p :if={@ticket.location && @ticket.location.path} class="text-xs text-base-content/50 mt-0.5">
              {@ticket.location.path}
            </p>
          </div>
          <a
            href={maps_url(@ticket)}
            target="_blank"
            rel="noopener"
            class="btn btn-sm btn-outline gap-1.5"
          >
            <.icon name="hero-map-pin" class="size-4" />
            Navigate
          </a>
        </div>
      </div>
    </div>
    """
  end

  attr :comments, :list, required: true
  attr :comment_body, :string, required: true

  defp comments_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-chat-bubble-left-right" class="size-4" />
          Activity & Comments
          <span class="badge badge-sm badge-ghost">{length(@comments)}</span>
        </h2>
      </div>
      <div class="p-6 space-y-4">
        <!-- Comment list -->
        <%= if @comments == [] do %>
          <div class="text-center py-6">
            <p class="text-sm text-base-content/40">No comments yet</p>
          </div>
        <% else %>
          <div class="space-y-3">
            <div :for={comment <- @comments} class={[
              "p-3.5 rounded-lg border",
              comment.type == "comment" && "bg-base-100 border-base-200",
              comment.type != "comment" && "bg-base-200/50 border-base-200"
            ]}>
              <div class="flex items-center justify-between mb-1.5">
                <div class="flex items-center gap-2">
                  <div :if={comment.user} class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center">
                    <span class="text-[10px] font-semibold text-primary">
                      {String.first(comment.user.name || comment.user.email) |> String.upcase()}
                    </span>
                  </div>
                  <span :if={comment.user} class="text-sm font-medium text-base-content">
                    {comment.user.name || comment.user.email}
                  </span>
                  <span :if={!comment.user} class="text-sm font-medium text-base-content/50 italic">System</span>
                  <span :if={comment.type != "comment"} class="badge badge-xs badge-ghost">
                    {String.replace(comment.type, "_", " ")}
                  </span>
                </div>
                <span class="text-xs text-base-content/40">
                  {format_datetime(comment.inserted_at)}
                </span>
              </div>
              <p class="text-sm text-base-content/80 leading-relaxed whitespace-pre-wrap">{comment.body}</p>
            </div>
          </div>
        <% end %>

        <!-- Add comment form -->
        <div class="pt-3 border-t border-base-200">
          <form phx-submit="add_comment" class="space-y-3">
            <textarea
              name="body"
              rows="3"
              placeholder="Add a comment..."
              value={@comment_body}
              class="textarea textarea-bordered w-full text-sm"
              required
            ></textarea>
            <div class="flex justify-end">
              <button type="submit" class="btn btn-sm btn-primary gap-1.5">
                <.icon name="hero-paper-airplane" class="size-4" />
                Add Comment
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # =============================================
  # Right Column Components
  # =============================================

  defp priority_selector(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-flag" class="size-4" />
          Priority
        </h2>
      </div>
      <div class="p-4">
        <div class="grid grid-cols-2 gap-2">
          <button
            :for={p <- ["emergency", "high", "medium", "low"]}
            phx-click="set_priority"
            phx-value-priority={p}
            class={[
              "btn btn-sm",
              @ticket.priority == p && priority_active_class(p),
              @ticket.priority != p && "btn-ghost"
            ]}
          >
            <span class={[
              "w-2 h-2 rounded-full mr-1.5",
              priority_dot_color(p)
            ]}></span>
            {String.capitalize(p)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp status_controls(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-arrow-path" class="size-4" />
          Status
        </h2>
      </div>
      <div class="p-4 space-y-2">
        <div class="flex items-center gap-2 mb-3">
          <.status_badge status={@ticket.status} />
          <span class="text-sm text-base-content/50">Current status</span>
        </div>

        <!-- Status transition buttons -->
        <div class="grid grid-cols-1 gap-2">
          <button
            :for={next_status <- next_statuses(@ticket.status)}
            phx-click="update_status"
            phx-value-status={next_status}
            class={["btn btn-sm btn-outline w-full gap-1.5", status_btn_color(next_status)]}
          >
            <.icon name={status_icon(next_status)} class="size-4" />
            {status_action_label(next_status)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :ticket, Ticket, required: true
  attr :contractor_orgs, :list, required: true

  defp assignment_section(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-user-plus" class="size-4" />
          Assignment
        </h2>
      </div>
      <div class="p-4 space-y-4">
        <!-- Current assignment -->
        <div :if={@ticket.assigned_to_user || @ticket.assigned_to_org} class="flex items-center gap-3 p-3 rounded-lg bg-base-200/50">
          <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
            <.icon name="hero-user" class="size-4 text-primary" />
          </div>
          <div class="min-w-0">
            <p :if={@ticket.assigned_to_user} class="text-sm font-medium text-base-content">
              {@ticket.assigned_to_user.name || @ticket.assigned_to_user.email}
            </p>
            <p :if={@ticket.assigned_to_org} class="text-xs text-base-content/50">
              {@ticket.assigned_to_org.name}
            </p>
          </div>
        </div>
        <div :if={!@ticket.assigned_to_user && !@ticket.assigned_to_org} class="text-sm text-base-content/40 italic px-1">
          Unassigned
        </div>

        <!-- Assign to contractor org -->
        <div>
          <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">
            Assign to Contractor
          </label>
          <select
            phx-change="assign_to_org"
            name="org_id"
            class="select select-bordered select-sm w-full"
          >
            <option value="">Select contractor...</option>
            <option
              :for={org <- @contractor_orgs}
              value={org.id}
              selected={@ticket.assigned_to_org_id == org.id}
            >
              {org.name}
            </option>
          </select>
        </div>

        <!-- Technician assignment is managed by the contractor admin -->
      </div>
    </div>
    """
  end

  defp sla_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-6 py-4 border-b border-base-300">
        <h2 class="text-base font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-clock" class="size-4" />
          SLA Timer
        </h2>
      </div>
      <div class="p-4">
        <%= if @ticket.sla_deadline do %>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <span class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Deadline</span>
              <span class={[
                "text-sm font-semibold",
                sla_breached?(@ticket) && "text-error",
                !sla_breached?(@ticket) && "text-base-content"
              ]}>
                {format_datetime(@ticket.sla_deadline)}
              </span>
            </div>

            <div class="flex items-center justify-between">
              <span class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Time Remaining</span>
              <span class={[
                "text-sm font-mono font-semibold",
                sla_breached?(@ticket) && "text-error",
                !sla_breached?(@ticket) && "text-success"
              ]}>
                {sla_time_remaining(@ticket)}
              </span>
            </div>

            <div :if={@ticket.sla_paused_at} class="flex items-center gap-2 text-xs text-warning">
              <.icon name="hero-pause-circle" class="size-4" />
              SLA paused
            </div>

            <div :if={@ticket.sla_breached} class="flex items-center gap-2 text-xs text-error font-medium">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              SLA breached
            </div>

            <div :if={@ticket.sla_started_at} class="text-xs text-base-content/40 pt-2 border-t border-base-200">
              Started {format_datetime(@ticket.sla_started_at)}
            </div>
          </div>
        <% else %>
          <div class="text-center py-4">
            <p class="text-sm text-base-content/40">
              Set a priority to start the SLA timer
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # =============================================
  # Shared Sub-Components
  # =============================================

  attr :status, :string, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @status == "created" && "badge-success badge-outline",
      @status == "triaged" && "badge-info badge-outline",
      @status == "assigned" && "badge-primary badge-outline",
      @status == "in_progress" && "badge-info",
      @status == "on_hold" && "badge-warning",
      @status == "completed" && "badge-success",
      @status == "reviewed" && "badge-success",
      @status == "closed" && "badge-ghost"
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  attr :priority, :string, default: nil

  defp priority_pill(assigns) do
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
      {String.capitalize(@priority)}
    </span>
    """
  end

  # =============================================
  # Event Handlers
  # =============================================

  @impl true
  def handle_event("set_priority", %{"priority" => priority}, socket) do
    ticket = socket.assigns.ticket

    case Tickets.set_priority(ticket, priority) do
      {:ok, updated_ticket} ->
        Tickets.log_activity(ticket.id, "status_change", "Priority set to #{priority}", %{
          field: "priority",
          old_value: ticket.priority,
          new_value: priority
        })

        updated_ticket = Tickets.get_ticket!(updated_ticket.id)
        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:ticket, updated_ticket)
         |> assign(:comments, comments)
         |> put_flash(:info, "Priority updated to #{priority}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update priority")}
    end
  end

  def handle_event("update_status", %{"status" => new_status}, socket) do
    ticket = socket.assigns.ticket
    old_status = ticket.status
    user = socket.assigns.current_user

    case Tickets.update_ticket_status(ticket, new_status, user) do
      {:ok, updated_ticket} ->
        Tickets.log_activity(ticket.id, "status_change", "Status changed from #{old_status} to #{new_status}", %{
          field: "status",
          old_value: old_status,
          new_value: new_status
        })

        updated_ticket = Tickets.get_ticket!(updated_ticket.id)
        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:ticket, updated_ticket)
         |> assign(:comments, comments)
         |> put_flash(:info, "Status updated to #{status_label(new_status)}")}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to make this status change")}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Proof of completion required. Please upload photos before marking as completed.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("assign_to_org", %{"org_id" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("assign_to_org", %{"org_id" => org_id}, socket) do
    ticket = socket.assigns.ticket
    user = socket.assigns.current_user

    case Tickets.assign_to_contractor_org(ticket, org_id, user) do
      {:ok, updated_ticket} ->
        updated_ticket = Tickets.get_ticket!(updated_ticket.id)
        org_name = if updated_ticket.assigned_to_org, do: updated_ticket.assigned_to_org.name, else: "contractor"

        Tickets.log_activity(ticket.id, "assignment", "Assigned to #{org_name}", %{
          field: "assigned_to_org_id",
          new_value: org_id
        })

        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:ticket, updated_ticket)
         |> assign(:comments, comments)
         |> put_flash(:info, "Assigned to #{org_name}")}

      {:error, :no_partnership} ->
        {:noreply, put_flash(socket, :error, "No active partnership with this contractor")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only admins can assign to contractors")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to assign ticket")}
    end
  end

  def handle_event("add_comment", %{"body" => body}, socket) do
    ticket = socket.assigns.ticket
    user = socket.assigns.current_user

    case Tickets.create_comment(%{
           ticket_id: ticket.id,
           user_id: user.id,
           body: body,
           type: "comment"
         }) do
      {:ok, _comment} ->
        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:comments, comments)
         |> assign(:comment_body, "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add comment")}
    end
  end

  def handle_event("toggle_on_hold", _params, socket) do
    ticket = socket.assigns.ticket

    if ticket.status == "on_hold" do
      # Resume — set back to in_progress and resume SLA
      with {:ok, updated_ticket} <- Tickets.update_ticket(ticket, %{status: "in_progress"}),
           {:ok, updated_ticket} <- Tickets.resume_sla(updated_ticket) do
        Tickets.log_activity(ticket.id, "status_change", "Resumed from on hold", %{
          field: "status",
          old_value: "on_hold",
          new_value: "in_progress"
        })

        updated_ticket = Tickets.get_ticket!(updated_ticket.id)
        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:ticket, updated_ticket)
         |> assign(:comments, comments)
         |> put_flash(:info, "Ticket resumed")}
      else
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to resume ticket")}
      end
    else
      # Put on hold and pause SLA
      with {:ok, updated_ticket} <- Tickets.update_ticket(ticket, %{status: "on_hold"}),
           {:ok, updated_ticket} <- Tickets.pause_sla(updated_ticket) do
        Tickets.log_activity(ticket.id, "status_change", "Put on hold", %{
          field: "status",
          old_value: ticket.status,
          new_value: "on_hold"
        })

        updated_ticket = Tickets.get_ticket!(updated_ticket.id)
        comments = Tickets.list_comments(ticket.id)

        {:noreply,
         socket
         |> assign(:ticket, updated_ticket)
         |> assign(:comments, comments)
         |> put_flash(:info, "Ticket put on hold")}
      else
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to put ticket on hold")}
      end
    end
  end

  # =============================================
  # Helpers
  # =============================================

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("pending_review"), do: "Pending Review"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(other)

  defp next_statuses(status) do
    StatusMachine.allowed_transitions("org_admin", status)
  end

  defp status_action_label("triaged"), do: "Mark as Triaged"
  defp status_action_label("assigned"), do: "Mark as Assigned"
  defp status_action_label("in_progress"), do: "Start Work"
  defp status_action_label("completed"), do: "Mark Complete"
  defp status_action_label("reviewed"), do: "Mark Reviewed"
  defp status_action_label("closed"), do: "Close Ticket"
  defp status_action_label(other), do: "Move to #{status_label(other)}"

  defp status_icon("triaged"), do: "hero-clipboard-document-check"
  defp status_icon("assigned"), do: "hero-user-plus"
  defp status_icon("in_progress"), do: "hero-play"
  defp status_icon("completed"), do: "hero-check-circle"
  defp status_icon("reviewed"), do: "hero-eye"
  defp status_icon("closed"), do: "hero-lock-closed"
  defp status_icon(_), do: "hero-arrow-right"

  defp status_btn_color("triaged"), do: "btn-info"
  defp status_btn_color("assigned"), do: "btn-primary"
  defp status_btn_color("in_progress"), do: "btn-info"
  defp status_btn_color("completed"), do: "btn-success"
  defp status_btn_color("reviewed"), do: "btn-success"
  defp status_btn_color("closed"), do: "btn-ghost"
  defp status_btn_color(_), do: ""

  defp priority_active_class("emergency"), do: "btn-error"
  defp priority_active_class("high"), do: "btn-warning"
  defp priority_active_class("medium"), do: "bg-amber-100 text-amber-700 border-amber-200"
  defp priority_active_class("low"), do: "btn-ghost btn-active"
  defp priority_active_class(_), do: "btn-ghost"

  defp priority_dot_color("emergency"), do: "bg-error"
  defp priority_dot_color("high"), do: "bg-warning"
  defp priority_dot_color("medium"), do: "bg-amber-500"
  defp priority_dot_color("low"), do: "bg-base-content/40"
  defp priority_dot_color(_), do: "bg-base-content/20"

  defp location_breadcrumb(location) do
    ancestors = build_ancestor_names(location, [])
    Enum.join(ancestors, " > ")
  end

  defp build_ancestor_names(nil, acc), do: acc

  defp build_ancestor_names(location, acc) do
    # Preload parent if not already loaded
    location = Fixly.Repo.preload(location, :parent)

    case location.parent do
      nil -> [location.name | acc]
      parent -> build_ancestor_names(parent, [location.name | acc])
    end
  end

  defp location_display_name(ticket) do
    cond do
      ticket.location -> ticket.location.name
      ticket.custom_location_name -> ticket.custom_location_name
      true -> "Unknown location"
    end
  end

  defp maps_url(ticket) do
    cond do
      ticket.location && ticket.location.metadata["gps_lat"] && ticket.location.metadata["gps_lng"] ->
        lat = ticket.location.metadata["gps_lat"]
        lng = ticket.location.metadata["gps_lng"]
        "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lng}"

      ticket.location ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.location.name)}"

      ticket.custom_location_name ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.custom_location_name)}"

      true ->
        "#"
    end
  end

  defp submitter_initial(ticket) do
    cond do
      ticket.submitter_name && ticket.submitter_name != "" ->
        ticket.submitter_name |> String.first() |> String.upcase()

      ticket.submitter_email && ticket.submitter_email != "" ->
        ticket.submitter_email |> String.first() |> String.upcase()

      true ->
        "?"
    end
  end

  defp file_icon(nil), do: "hero-document"
  defp file_icon(type) do
    cond do
      String.contains?(type, "image") -> "hero-photo"
      String.contains?(type, "pdf") -> "hero-document-text"
      String.contains?(type, "video") -> "hero-video-camera"
      true -> "hero-document"
    end
  end

  defp format_file_size(nil), do: ""
  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_datetime(nil), do: ""
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp sla_breached?(ticket) do
    ticket.sla_breached ||
      (ticket.sla_deadline && DateTime.compare(DateTime.utc_now(), ticket.sla_deadline) == :gt)
  end

  defp sla_time_remaining(ticket) do
    if ticket.sla_deadline do
      now = DateTime.utc_now()
      diff = DateTime.diff(ticket.sla_deadline, now, :second)

      if diff <= 0 do
        "OVERDUE"
      else
        hours = div(diff, 3600)
        minutes = div(rem(diff, 3600), 60)

        cond do
          hours >= 24 -> "#{div(hours, 24)}d #{rem(hours, 24)}h"
          hours > 0 -> "#{hours}h #{minutes}m"
          true -> "#{minutes}m"
        end
      end
    else
      "N/A"
    end
  end
end
