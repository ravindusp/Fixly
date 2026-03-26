defmodule FixlyWeb.Technician.MyTicketsLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.{Ticket, StatusMachine}
  alias Fixly.PubSubBroadcast

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    if connected?(socket) do
      PubSubBroadcast.subscribe_user(user.id)
    end

    socket =
      socket
      |> assign(:page_title, "My Tickets")
      |> assign(:user, user)
      |> assign(:tab, "active")
      |> assign(:selected_ticket, nil)
      |> assign(:comments, [])
      |> assign(:comment_body, "")
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:active_count, 0)
      |> assign(:completed_count, 0)
      |> allow_upload(:proof, accept: ~w(.jpg .jpeg .png .webp), max_entries: 5, max_file_size: 10_000_000)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def handle_info({:ticket_updated, _ticket}, socket) do
    socket =
      if socket.assigns.selected_ticket do
        ticket = Tickets.get_ticket!(socket.assigns.selected_ticket.id)
        comments = Tickets.list_comments(ticket.id)
        assign(socket, selected_ticket: ticket, comments: comments)
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
      <div class="flex-1 min-w-0 space-y-4">
        <!-- Header with tabs -->
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-base-content">My Tickets</h2>
            <p class="text-sm text-base-content/50">{@active_count} active, {@completed_count} completed</p>
          </div>
          <div class="flex items-center gap-1 bg-base-200 rounded-lg p-0.5">
            <button
              phx-click="switch_tab"
              phx-value-tab="active"
              class={["btn btn-sm gap-1.5", @tab == "active" && "btn-active", @tab != "active" && "btn-ghost"]}
            >
              <.icon name="hero-inbox-stack" class="size-3.5" />
              Active
              <span :if={@active_count > 0} class="badge badge-xs badge-primary">{@active_count}</span>
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="completed"
              class={["btn btn-sm gap-1.5", @tab == "completed" && "btn-active", @tab != "completed" && "btn-ghost"]}
            >
              <.icon name="hero-check-circle" class="size-3.5" />
              Completed
            </button>
          </div>
        </div>

        <!-- Ticket list -->
        <div id="technician-tickets-stream" phx-update="stream" class="space-y-3">
          <div
            :for={{dom_id, ticket} <- @streams.tickets}
            id={dom_id}
            phx-click="select_ticket"
            phx-value-id={ticket.id}
            class={[
              "bg-base-100 rounded-xl border shadow-sm overflow-hidden cursor-pointer transition-all",
              @selected_ticket && @selected_ticket.id == ticket.id && "border-primary ring-1 ring-primary/20",
              !(@selected_ticket && @selected_ticket.id == ticket.id) && "border-base-300 hover:shadow-md"
            ]}
          >
            <div class="px-4 py-3.5">
              <div class="flex items-start justify-between gap-3">
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 mb-1">
                    <span class="text-xs font-mono text-base-content/40">{ticket.reference_number}</span>
                    <.priority_badge priority={ticket.priority} />
                    <span class={[
                      "badge badge-xs",
                      ticket.status == "assigned" && "badge-primary badge-outline",
                      ticket.status == "in_progress" && "badge-info",
                      ticket.status == "on_hold" && "badge-warning",
                      ticket.status in ["completed", "reviewed", "closed"] && "badge-ghost"
                    ]}>
                      {status_label(ticket.status)}
                    </span>
                  </div>
                  <p class="text-sm font-medium text-base-content leading-snug">
                    {truncate(ticket.description, 100)}
                  </p>
                  <div class="flex items-center gap-3 mt-2">
                    <div :if={ticket.location} class="flex items-center gap-1 text-xs text-base-content/50">
                      <.icon name="hero-map-pin" class="size-3" />
                      <span>{ticket.location.name}</span>
                    </div>
                    <div :if={ticket.sla_deadline && @tab == "active"} class="flex items-center gap-1 text-xs">
                      <.icon name="hero-clock" class={["size-3", sla_urgency_color(ticket)]} />
                      <span class={sla_urgency_color(ticket)}>{sla_remaining_text(ticket)}</span>
                    </div>
                    <div :if={@tab == "completed"} class="text-xs text-base-content/40">
                      {Calendar.strftime(ticket.updated_at, "%b %d, %Y")}
                    </div>
                  </div>
                </div>
                <.icon name="hero-chevron-right" class="size-4 text-base-content/30 mt-1 shrink-0" />
              </div>
            </div>
          </div>
        </div>

        <!-- Empty state -->
        <div :if={(@tab == "active" && @active_count == 0) || (@tab == "completed" && @completed_count == 0)} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="flex flex-col items-center justify-center py-16 text-center">
            <div class={["w-14 h-14 rounded-2xl flex items-center justify-center mb-4", @tab == "active" && "bg-success/10", @tab == "completed" && "bg-base-200"]}>
              <.icon name={if @tab == "active", do: "hero-check-circle", else: "hero-archive-box"} class={["size-7", @tab == "active" && "text-success", @tab == "completed" && "text-base-content/30"]} />
            </div>
            <h3 class="text-base font-semibold text-base-content mb-1">
              {if @tab == "active", do: "All caught up!", else: "No completed tickets yet"}
            </h3>
            <p class="text-sm text-base-content/50">
              {if @tab == "active", do: "No tickets assigned to you right now.", else: "Completed tickets will appear here."}
            </p>
          </div>
        </div>

        <!-- Infinite scroll -->
        <div
          :if={@has_more}
          id="technician-tickets-scroll"
          phx-hook="InfiniteScroll"
          data-has-more={to_string(@has_more)}
          class="flex justify-center py-4"
        >
          <span class="loading loading-spinner loading-sm text-base-content/30"></span>
        </div>
      </div>

      <!-- Detail panel -->
      <.ticket_detail
        :if={@selected_ticket}
        ticket={@selected_ticket}
        comments={@comments}
        comment_body={@comment_body}
        uploads={@uploads}
        tab={@tab}
      />
    </div>
    """
  end

  # --- Detail Panel ---

  attr :ticket, Ticket, required: true
  attr :comments, :list, required: true
  attr :comment_body, :string, required: true
  attr :uploads, :any, required: true
  attr :tab, :string, required: true

  defp ticket_detail(assigns) do
    ~H"""
    <div class="w-full lg:w-[420px] shrink-0 bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-y-auto max-h-[calc(100vh-7rem)] animate-in slide-in-from-right">
      <!-- Header -->
      <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-5 py-3.5">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <span class="text-base font-bold text-base-content">{@ticket.reference_number}</span>
            <span class={[
              "badge badge-sm",
              @ticket.status == "assigned" && "badge-primary badge-outline",
              @ticket.status == "in_progress" && "badge-info",
              @ticket.status == "on_hold" && "badge-warning",
              @ticket.status in ["completed", "reviewed", "closed"] && "badge-ghost"
            ]}>
              {status_label(@ticket.status)}
            </span>
          </div>
          <button phx-click="close_panel" class="btn btn-ghost btn-xs btn-square">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>

      <div class="p-5 space-y-5">
        <!-- Info -->
        <div class="space-y-3">
          <div :if={@ticket.priority} class="flex justify-between items-center">
            <span class="text-xs text-base-content/50">Priority</span>
            <.priority_badge priority={@ticket.priority} />
          </div>
          <div :if={@ticket.location} class="flex justify-between items-center">
            <span class="text-xs text-base-content/50">Location</span>
            <div class="flex items-center gap-1.5 text-sm text-base-content">
              <.icon name="hero-map-pin" class="size-3.5 text-base-content/40" />
              <span>{@ticket.location.name}</span>
            </div>
          </div>
          <div :if={@ticket.category} class="flex justify-between items-center">
            <span class="text-xs text-base-content/50">Category</span>
            <span class="badge badge-sm badge-ghost">{String.capitalize(@ticket.category)}</span>
          </div>
          <div :if={@ticket.sla_deadline} class="flex justify-between items-center">
            <span class="text-xs text-base-content/50">SLA Deadline</span>
            <span class={["text-sm font-medium", sla_urgency_color(@ticket)]}>
              {sla_remaining_text(@ticket)}
            </span>
          </div>
          <div :if={@ticket.submitter_name} class="flex justify-between items-center">
            <span class="text-xs text-base-content/50">Reported by</span>
            <div class="flex items-center gap-2">
              <span class="text-sm text-base-content">{@ticket.submitter_name}</span>
              <a :if={@ticket.submitter_phone} href={"tel:#{@ticket.submitter_phone}"} class="btn btn-xs btn-ghost btn-square">
                <.icon name="hero-phone" class="size-3" />
              </a>
            </div>
          </div>
        </div>

        <!-- Description -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Description</p>
          <p class="text-sm text-base-content leading-relaxed bg-base-200/40 rounded-lg p-3">
            {@ticket.description}
          </p>
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

        <!-- Proof photos -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">
            Proof of Completion
            <span :if={@ticket.attachments != []} class="badge badge-xs badge-ghost ml-1">{length(@ticket.attachments)}</span>
          </p>
          <div :if={@ticket.attachments != []} class="grid grid-cols-3 gap-2 mb-3">
            <div
              :for={att <- @ticket.attachments}
              class="aspect-square rounded-lg overflow-hidden border border-base-200"
            >
              <img src={att.file_url} alt={att.file_name} class="w-full h-full object-cover" />
            </div>
          </div>

          <!-- Upload form (only on active tab) -->
          <div :if={@tab == "active"}>
            <form id={"upload-#{@ticket.id}"} phx-submit="upload_proof" phx-change="validate_upload" class="space-y-2">
              <.live_file_input upload={@uploads.proof} class="file-input file-input-bordered file-input-xs w-full" />
              <div :for={entry <- @uploads.proof.entries} class="flex items-center gap-2 text-xs text-base-content/60">
                <span class="truncate">{entry.client_name}</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-error">&times;</button>
              </div>
              <button :if={@uploads.proof.entries != []} type="submit" class="btn btn-xs btn-primary w-full gap-1">
                <.icon name="hero-arrow-up-tray" class="size-3" />
                Upload Photos
              </button>
            </form>
          </div>
          <p :if={@ticket.attachments == [] && @tab == "completed"} class="text-xs text-base-content/40 text-center py-2">No proof uploaded</p>
        </div>

        <!-- Status actions (only on active tab) -->
        <div :if={@tab == "active" && StatusMachine.allowed_transitions("technician", @ticket.status) != []}>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Actions</p>
          <div class="flex gap-2">
            <button
              :for={s <- StatusMachine.allowed_transitions("technician", @ticket.status)}
              phx-click="update_status"
              phx-value-id={@ticket.id}
              phx-value-status={s}
              class={[
                "btn btn-sm flex-1 gap-1.5",
                s == "in_progress" && "btn-primary",
                s == "on_hold" && "btn-warning btn-outline",
                s == "completed" && "btn-success"
              ]}
            >
              <.icon name={status_action_icon(s)} class="size-4" />
              {status_action_label(s)}
            </button>
          </div>
        </div>

        <!-- Comments / Notes -->
        <div>
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">
            Notes
            <span :if={@comments != []} class="badge badge-xs badge-ghost ml-1">{length(@comments)}</span>
          </p>

          <!-- Comment list -->
          <div :if={@comments != []} class="space-y-2 mb-3 max-h-48 overflow-y-auto">
            <div :for={comment <- @comments} class={[
              "rounded-lg p-2.5 text-xs",
              comment.type == "comment" && "bg-base-200/50",
              comment.type != "comment" && "bg-base-200/30 text-base-content/50 italic"
            ]}>
              <div class="flex justify-between items-start mb-1">
                <span class="font-medium text-base-content/70">{comment_author(comment)}</span>
                <span class="text-base-content/30 text-[10px]">{Calendar.strftime(comment.inserted_at, "%b %d, %I:%M %p")}</span>
              </div>
              <p class="text-base-content/80">{comment.body}</p>
            </div>
          </div>
          <p :if={@comments == []} class="text-xs text-base-content/40 text-center py-2 mb-3">No notes yet</p>

          <!-- Add comment -->
          <form phx-submit="add_comment" class="flex gap-2">
            <input
              type="text"
              name="body"
              value={@comment_body}
              placeholder="Add a note..."
              class="input input-bordered input-xs flex-1"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-xs btn-primary btn-square">
              <.icon name="hero-paper-airplane" class="size-3" />
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

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
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:selected_ticket, nil)
     |> assign(:comments, [])
     |> reload_data()}
  end

  def handle_event("select_ticket", %{"id" => id}, socket) do
    ticket = Tickets.get_ticket!(id)
    comments = Tickets.list_comments(id)
    {:noreply, assign(socket, selected_ticket: ticket, comments: comments, comment_body: "")}
  end

  def handle_event("close_panel", _params, socket) do
    {:noreply, assign(socket, selected_ticket: nil, comments: [], comment_body: "")}
  end

  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      page =
        if socket.assigns.tab == "active" do
          Tickets.list_user_tickets_paginated(socket.assigns.user.id, socket.assigns.cursor)
        else
          Tickets.list_user_completed_tickets_paginated(socket.assigns.user.id, socket.assigns.cursor)
        end

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:tickets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :proof, ref)}
  end

  def handle_event("upload_proof", _params, socket) do
    ticket = socket.assigns.selected_ticket
    upload_dir = Fixly.Uploads.dir("proof")
    File.mkdir_p!(upload_dir)

    uploaded_files =
      consume_uploaded_entries(socket, :proof, fn %{path: path}, entry ->
        dest = Path.join(upload_dir, "#{Ecto.UUID.generate()}_#{entry.client_name}")
        File.cp!(path, dest)
        {:ok, "/uploads/proof/#{Path.basename(dest)}"}
      end)

    for file_url <- uploaded_files do
      Tickets.create_attachment(%{
        ticket_id: ticket.id,
        file_url: file_url,
        file_name: Path.basename(file_url),
        file_type: "image"
      })
    end

    updated = Tickets.get_ticket!(ticket.id)

    {:noreply,
     socket
     |> assign(:selected_ticket, updated)
     |> put_flash(:info, "#{length(uploaded_files)} photo(s) uploaded")
     |> reload_data()}
  end

  def handle_event("add_comment", %{"body" => body}, socket) when byte_size(body) > 0 do
    ticket = socket.assigns.selected_ticket
    user = socket.assigns.user

    case Tickets.create_comment(%{
      ticket_id: ticket.id,
      user_id: user.id,
      body: body,
      type: "comment"
    }) do
      {:ok, _comment} ->
        comments = Tickets.list_comments(ticket.id)
        {:noreply, assign(socket, comments: comments, comment_body: "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add note")}
    end
  end

  def handle_event("add_comment", _params, socket), do: {:noreply, socket}

  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    ticket = Tickets.get_ticket!(id)
    user = socket.assigns.user

    case Tickets.update_ticket_status(ticket, status, user) do
      {:ok, _} ->
        Tickets.log_activity(id, "status_change", "Status changed to #{status_label(status)}", %{
          from: ticket.status,
          to: status,
          changed_by: user.name || user.email
        })

        updated = Tickets.get_ticket!(id)
        PubSubBroadcast.broadcast_ticket_updated(updated)
        comments = Tickets.list_comments(id)

        {:noreply,
         socket
         |> assign(:selected_ticket, updated)
         |> assign(:comments, comments)
         |> put_flash(:info, "Status updated to #{status_label(status)}")
         |> reload_data()}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Please upload proof photos before marking as completed")}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot make this status change")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  # --- Helpers ---

  defp reload_data(socket) do
    user = socket.assigns.user
    active_count = Tickets.count_user_tickets(user.id)
    completed_count = Tickets.count_user_completed_tickets(user.id)

    page =
      if socket.assigns.tab == "active" do
        Tickets.list_user_tickets_paginated(user.id)
      else
        Tickets.list_user_completed_tickets_paginated(user.id)
      end

    socket
    |> assign(:active_count, active_count)
    |> assign(:completed_count, completed_count)
    |> assign(:cursor, page.cursor)
    |> assign(:has_more, page.has_more)
    |> stream(:tickets, page.entries, reset: true)
  end

  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(other)

  defp status_action_label("in_progress"), do: "Start Work"
  defp status_action_label("on_hold"), do: "Pause"
  defp status_action_label("completed"), do: "Mark Complete"
  defp status_action_label(s), do: String.capitalize(s)

  defp status_action_icon("in_progress"), do: "hero-play"
  defp status_action_icon("on_hold"), do: "hero-pause"
  defp status_action_icon("completed"), do: "hero-check"
  defp status_action_icon(_), do: "hero-arrow-right"

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(_), do: "System"

  defp sla_remaining_text(%{sla_deadline: nil}), do: "No deadline"
  defp sla_remaining_text(%{sla_paused_at: paused_at}) when not is_nil(paused_at), do: "Paused"
  defp sla_remaining_text(%{sla_deadline: deadline}) do
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
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
    diff = DateTime.diff(deadline, DateTime.utc_now(), :minute)
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

  defp maps_url(ticket) do
    cond do
      ticket.location && ticket.location.metadata["gps_lat"] && ticket.location.metadata["gps_lng"] ->
        "https://www.google.com/maps/dir/?api=1&destination=#{ticket.location.metadata["gps_lat"]},#{ticket.location.metadata["gps_lng"]}"
      ticket.location ->
        "https://www.google.com/maps/search/?api=1&query=#{URI.encode(ticket.location.name)}"
      true ->
        "#"
    end
  end
end
