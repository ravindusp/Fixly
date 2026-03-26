defmodule FixlyWeb.Technician.MyTicketsLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.{Ticket, StatusMachine}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    socket =
      socket
      |> assign(:page_title, "My Tickets")
      |> assign(:user, user)
      |> assign(:selected_ticket_id, nil)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:ticket_count, 0)
      |> allow_upload(:proof, accept: ~w(.jpg .jpeg .png .webp), max_entries: 5, max_file_size: 10_000_000)
      |> reload_data()

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
          <p class="text-sm text-base-content/50">{@ticket_count} active tickets assigned to you</p>
        </div>
      </div>

      <div id="technician-tickets-stream" phx-update="stream">
        <.ticket_card
          :for={{dom_id, ticket} <- @streams.tickets}
          id={dom_id}
          ticket={ticket}
          expanded={@selected_ticket_id == ticket.id}
          uploads={@uploads}
        />
      </div>

      <!-- Empty state -->
      <div :if={@ticket_count == 0} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="flex flex-col items-center justify-center py-16 text-center">
          <div class="w-14 h-14 rounded-2xl bg-success/10 flex items-center justify-center mb-4">
            <.icon name="hero-check-circle" class="size-7 text-success" />
          </div>
          <h3 class="text-base font-semibold text-base-content mb-1">All caught up!</h3>
          <p class="text-sm text-base-content/50">No tickets assigned to you right now.</p>
        </div>
      </div>

      <!-- Infinite scroll sentinel -->
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
    """
  end

  # --- Ticket Card (mobile-first design) ---

  attr :id, :string, required: true
  attr :ticket, Ticket, required: true
  attr :expanded, :boolean, default: false
  attr :uploads, :any, required: true

  defp ticket_card(assigns) do
    ~H"""
    <div id={@id} class="bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-hidden mb-3">
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
            href={maps_url(@ticket)}
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

        <!-- Upload proof -->
        <div :if={@expanded} class="px-4 py-3 border-t border-base-200">
          <p class="text-xs font-medium text-base-content/50 mb-2">Upload Proof of Completion</p>
          <form id={"upload-#{@ticket.id}"} phx-submit="upload_proof" phx-value-ticket-id={@ticket.id} phx-change="validate_upload">
            <.live_file_input upload={@uploads.proof} class="file-input file-input-bordered file-input-xs w-full" />
            <div :for={entry <- @uploads.proof.entries} class="flex items-center gap-2 mt-2 text-xs text-base-content/60">
              <span>{entry.client_name}</span>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-error">&times;</button>
            </div>
            <button :if={@uploads.proof.entries != []} type="submit" class="btn btn-xs btn-outline btn-primary mt-2">
              Upload
            </button>
          </form>
        </div>

        <!-- Action buttons -->
        <div class="px-4 py-3 bg-base-200/30 flex flex-wrap gap-2">
          <button
            :for={s <- StatusMachine.allowed_transitions("technician", @ticket.status)}
            phx-click="update_status"
            phx-value-id={@ticket.id}
            phx-value-status={s}
            class={[
              "btn btn-sm flex-1",
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
  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      page = Tickets.list_user_tickets_paginated(socket.assigns.user.id, socket.assigns.cursor)

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:tickets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :proof, ref)}
  end

  def handle_event("upload_proof", %{"ticket-id" => ticket_id}, socket) do
    # Ensure uploads directory exists
    upload_dir = Path.join(["priv", "static", "uploads", "proof"])
    File.mkdir_p!(upload_dir)

    uploaded_files =
      consume_uploaded_entries(socket, :proof, fn %{path: path}, entry ->
        dest = Path.join(upload_dir, "#{Ecto.UUID.generate()}_#{entry.client_name}")
        File.cp!(path, dest)
        {:ok, "/uploads/proof/#{Path.basename(dest)}"}
      end)

    for file_url <- uploaded_files do
      Tickets.create_attachment(%{
        ticket_id: ticket_id,
        file_url: file_url,
        file_name: Path.basename(file_url),
        file_type: "image"
      })
    end

    {:noreply,
     socket
     |> put_flash(:info, "#{length(uploaded_files)} file(s) uploaded")
     |> reload_data()}
  end

  def handle_event("toggle_ticket", %{"id" => id}, socket) do
    selected =
      if socket.assigns.selected_ticket_id == id, do: nil, else: id

    {:noreply, assign(socket, :selected_ticket_id, selected)}
  end

  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    ticket = Tickets.get_ticket!(id)
    user = socket.assigns.user

    case Tickets.update_ticket_status(ticket, status, user) do
      {:ok, _} ->
        Tickets.log_activity(id, "status_change", "Status changed to #{status}", %{
          from: ticket.status,
          to: status
        })

        {:noreply, reload_data(socket)}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to make this status change")}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Please upload proof of completion before marking as completed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  # --- Helpers ---

  defp reload_data(socket) do
    user = socket.assigns.user
    count = Tickets.count_user_tickets(user.id)
    page = Tickets.list_user_tickets_paginated(user.id)

    socket
    |> assign(:ticket_count, count)
    |> assign(:cursor, page.cursor)
    |> assign(:has_more, page.has_more)
    |> stream(:tickets, page.entries, reset: true)
  end

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

  defp status_action_label("in_progress"), do: "Start Work"
  defp status_action_label("on_hold"), do: "On Hold"
  defp status_action_label("completed"), do: "Complete"
  defp status_action_label(s), do: String.capitalize(s)

  defp status_action_icon("in_progress"), do: "hero-play"
  defp status_action_icon("on_hold"), do: "hero-pause"
  defp status_action_icon("completed"), do: "hero-check"
  defp status_action_icon(_), do: "hero-arrow-right"

  defp truncate(nil, _), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."

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
end
