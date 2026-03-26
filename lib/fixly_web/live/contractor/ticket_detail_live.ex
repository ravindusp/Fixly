defmodule FixlyWeb.Contractor.TicketDetailLive do
  use FixlyWeb, :live_view

  alias Fixly.Tickets
  alias Fixly.Tickets.StatusMachine
  alias Fixly.Accounts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    ticket = Tickets.get_ticket!(id)
    comments = Tickets.list_comments(id)
    user = socket.assigns.current_scope.user
    technicians = if user.organization_id, do: Accounts.list_technicians_by_organization(user.organization_id), else: []

    socket =
      socket
      |> assign(:page_title, ticket.reference_number)
      |> assign(:ticket, ticket)
      |> assign(:comments, comments)
      |> assign(:technicians, technicians)
      |> assign(:comment_body, "")
      |> allow_upload(:proof, accept: ~w(.jpg .jpeg .png .webp), max_entries: 5, max_file_size: 10_000_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Back link -->
      <.link navigate={~p"/contractor/tickets"} class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-base-content transition-colors">
        <.icon name="hero-arrow-left" class="size-4" />
        Back to Tickets
      </.link>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Main content -->
        <div class="lg:col-span-2 space-y-4">
          <!-- Ticket header -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <div class="flex items-center gap-3 mb-3">
              <span class="text-lg font-bold text-base-content">{@ticket.reference_number}</span>
              <span class={[
                "badge font-medium",
                status_badge_class(@ticket.status)
              ]}>{status_label(@ticket.status)}</span>
              <span :if={@ticket.priority} class={[
                "badge font-medium",
                priority_badge_class(@ticket.priority)
              ]}>{String.capitalize(@ticket.priority)}</span>
            </div>

            <p class="text-base text-base-content leading-relaxed">{@ticket.description}</p>

            <div class="mt-4 flex flex-wrap gap-4 text-sm text-base-content/60">
              <div :if={@ticket.location} class="flex items-center gap-1.5">
                <.icon name="hero-map-pin" class="size-4" />
                <span>{@ticket.location.name}</span>
              </div>
              <div :if={@ticket.category} class="flex items-center gap-1.5">
                <.icon name="hero-tag" class="size-4" />
                <span>{@ticket.category}</span>
              </div>
              <div class="flex items-center gap-1.5">
                <.icon name="hero-calendar" class="size-4" />
                <span>{Calendar.strftime(@ticket.inserted_at, "%b %d, %Y at %I:%M %p")}</span>
              </div>
            </div>
          </div>

          <!-- Submitter -->
          <div :if={@ticket.submitter_name} class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-3">Reported By</h3>
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-full bg-base-200 flex items-center justify-center">
                <.icon name="hero-user" class="size-5 text-base-content/40" />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content">{@ticket.submitter_name}</p>
                <p :if={@ticket.submitter_phone} class="text-xs text-base-content/50">
                  <a href={"tel:#{@ticket.submitter_phone}"} class="text-primary hover:underline">{@ticket.submitter_phone}</a>
                </p>
              </div>
            </div>
          </div>

          <!-- Navigate -->
          <div :if={@ticket.location} class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <a
              href={"https://www.google.com/maps/search/?api=1&query=#{URI.encode(@ticket.location.name)}"}
              target="_blank"
              class="btn btn-outline btn-primary w-full gap-2"
            >
              <.icon name="hero-map-pin" class="size-5" />
              Navigate to Location
            </a>
          </div>
        </div>

        <!-- Sidebar -->
        <div class="space-y-4">
          <!-- Assignment -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-3">Assign Technician</h3>
            <select
              class="select select-bordered w-full"
              phx-change="assign_technician"
              name="user_id"
            >
              <option value="">Unassigned</option>
              <option
                :for={tech <- @technicians}
                value={tech.id}
                selected={@ticket.assigned_to_user_id == tech.id}
              >
                {tech.name || tech.email}
              </option>
            </select>
          </div>

          <!-- Status -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-3">Update Status</h3>
            <div class="flex flex-wrap gap-2">
              <button
                :for={s <- StatusMachine.allowed_transitions("contractor_admin", @ticket.status)}
                phx-click="update_status"
                phx-value-status={s}
                class={["btn btn-sm", @ticket.status == s && "btn-primary", @ticket.status != s && "btn-ghost"]}
              >
                {status_label(s)}
              </button>
              <p :if={StatusMachine.allowed_transitions("contractor_admin", @ticket.status) == []} class="text-xs text-base-content/40">
                No status changes available
              </p>
            </div>
          </div>

          <!-- Upload proof -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-3">Upload Proof</h3>
            <form id="contractor-upload-proof" phx-submit="upload_proof" phx-change="validate_upload">
              <.live_file_input upload={@uploads.proof} class="file-input file-input-bordered file-input-xs w-full" />
              <div :for={entry <- @uploads.proof.entries} class="flex items-center gap-2 mt-2 text-xs text-base-content/60">
                <span>{entry.client_name}</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-error">&times;</button>
              </div>
              <button :if={@uploads.proof.entries != []} type="submit" class="btn btn-xs btn-outline btn-primary mt-2 w-full">
                Upload Files
              </button>
            </form>
          </div>

          <!-- SLA -->
          <div :if={@ticket.sla_deadline} class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-2">SLA Deadline</h3>
            <p class="text-sm text-base-content/70">
              {Calendar.strftime(@ticket.sla_deadline, "%b %d, %Y at %I:%M %p")}
            </p>
          </div>

          <!-- Comments -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
            <h3 class="text-sm font-semibold text-base-content mb-3">Notes</h3>
            <div class="space-y-3 mb-4">
              <div :for={comment <- @comments} class="text-sm">
                <div class="flex items-center gap-2 mb-0.5">
                  <span class="font-medium text-base-content">{comment_author(comment)}</span>
                  <span class="text-xs text-base-content/40">{Calendar.strftime(comment.inserted_at, "%b %d %I:%M %p")}</span>
                </div>
                <p class="text-base-content/70">{comment.body}</p>
              </div>
              <p :if={@comments == []} class="text-sm text-base-content/40">No notes yet.</p>
            </div>
            <form phx-submit="add_comment" class="flex gap-2">
              <input
                type="text"
                name="body"
                value={@comment_body}
                placeholder="Add a note..."
                class="input input-sm input-bordered flex-1"
              />
              <button type="submit" class="btn btn-sm btn-primary">Send</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("assign_technician", %{"user_id" => ""}, socket) do
    {:ok, ticket} = Tickets.update_ticket(socket.assigns.ticket, %{assigned_to_user_id: nil})
    {:noreply, assign(socket, :ticket, Tickets.get_ticket!(ticket.id))}
  end

  def handle_event("assign_technician", %{"user_id" => user_id}, socket) do
    ticket = socket.assigns.ticket
    user = socket.assigns.current_scope.user

    case Tickets.assign_to_technician(ticket, user_id, user) do
      {:ok, _} ->
        {:noreply, assign(socket, :ticket, Tickets.get_ticket!(ticket.id))}

      {:error, :not_your_ticket} ->
        {:noreply, put_flash(socket, :error, "This ticket is not assigned to your organization")}

      {:error, :tech_not_in_org} ->
        {:noreply, put_flash(socket, :error, "This technician is not in your organization")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to assign technician")}
    end
  end

  def handle_event("update_status", %{"status" => status}, socket) do
    ticket = socket.assigns.ticket
    user = socket.assigns.current_scope.user

    case Tickets.update_ticket_status(ticket, status, user) do
      {:ok, updated} ->
        {:noreply, assign(socket, :ticket, Tickets.get_ticket!(updated.id))}

      {:error, :unauthorized_transition} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to make this status change")}

      {:error, :proof_required} ->
        {:noreply, put_flash(socket, :error, "Please upload proof of completion (photos) before marking as completed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("add_comment", %{"body" => body}, socket) when body != "" do
    user = socket.assigns.current_scope.user

    {:ok, _} = Tickets.create_comment(%{
      ticket_id: socket.assigns.ticket.id,
      user_id: user.id,
      body: body
    })

    comments = Tickets.list_comments(socket.assigns.ticket.id)
    {:noreply, socket |> assign(:comments, comments) |> assign(:comment_body, "")}
  end

  def handle_event("add_comment", _, socket), do: {:noreply, socket}

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :proof, ref)}
  end

  def handle_event("upload_proof", _params, socket) do
    ticket = socket.assigns.ticket
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
        ticket_id: ticket.id,
        file_url: file_url,
        file_name: Path.basename(file_url),
        file_type: "image"
      })
    end

    updated_ticket = Tickets.get_ticket!(ticket.id)

    {:noreply,
     socket
     |> assign(:ticket, updated_ticket)
     |> put_flash(:info, "#{length(uploaded_files)} file(s) uploaded")}
  end

  # --- Helpers ---

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
  defp status_badge_class("in_progress"), do: "badge-info"
  defp status_badge_class("on_hold"), do: "badge-warning"
  defp status_badge_class("completed"), do: "badge-ghost"
  defp status_badge_class(_), do: "badge-primary badge-outline"

  defp priority_badge_class("emergency"), do: "badge-error"
  defp priority_badge_class("high"), do: "badge-warning"
  defp priority_badge_class("medium"), do: "bg-amber-100 text-amber-700 border-amber-200"
  defp priority_badge_class("low"), do: "badge-ghost"
  defp priority_badge_class(_), do: "badge-ghost"

  defp comment_author(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(_), do: "System"
end
