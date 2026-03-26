defmodule FixlyWeb.Contractor.TeamLive do
  use FixlyWeb, :live_view

  alias Fixly.Accounts
  alias Fixly.Organizations

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    socket =
      socket
      |> assign(:page_title, "Team")
      |> assign(:org_id, org_id)
      |> assign(:current_user, user)
      |> assign(:invite_form, to_form(%{"email" => "", "name" => ""}))
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-base-content">Team Management</h2>
          <p class="text-sm text-base-content/50">Manage your technicians</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Invite form (technicians only) -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content">Invite Technician</h3>
          </div>
          <div class="p-5">
            <.form for={@invite_form} phx-submit="send_invite" class="space-y-4">
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Name</label>
                <input
                  type="text"
                  name="name"
                  value={@invite_form[:name].value}
                  required
                  placeholder="Full name"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Email</label>
                <input
                  type="email"
                  name="email"
                  value={@invite_form[:email].value}
                  required
                  placeholder="name@company.com"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm w-full gap-1.5">
                <.icon name="hero-paper-airplane" class="size-4" />
                Send Invite
              </button>
            </.form>
          </div>
        </div>

        <!-- Team members list -->
        <div class="lg:col-span-2 space-y-4">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Team Members
                <span class="badge badge-sm badge-ghost ml-1">{length(@members)}</span>
              </h3>
            </div>
            <div class="divide-y divide-base-200">
              <div :for={member <- @members} class="px-5 py-3 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center">
                    <span class="text-xs font-semibold text-primary">
                      {member.name |> String.first() |> String.upcase()}
                    </span>
                  </div>
                  <div>
                    <p class="text-sm font-medium text-base-content">{member.name}</p>
                    <p class="text-xs text-base-content/50">{member.email}</p>
                  </div>
                </div>
                <span class={["badge badge-sm", if(member.role == "contractor_admin", do: "badge-primary", else: "badge-success")]}>
                  {if member.role == "contractor_admin", do: "Admin", else: "Technician"}
                </span>
              </div>
              <div :if={@members == []} class="px-5 py-8 text-center text-sm text-base-content/40">
                No team members yet.
              </div>
            </div>
          </div>

          <!-- Pending invites -->
          <div :if={@pending_invites != []} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Pending Invites
                <span class="badge badge-sm badge-warning ml-1">{length(@pending_invites)}</span>
              </h3>
            </div>
            <div class="divide-y divide-base-200">
              <div :for={invite <- @pending_invites} class="px-5 py-3 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-full bg-warning/10 flex items-center justify-center">
                    <.icon name="hero-envelope" class="size-4 text-warning" />
                  </div>
                  <div>
                    <p class="text-sm font-medium text-base-content">{invite.name}</p>
                    <p class="text-xs text-base-content/50">{invite.email}</p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-base-content/40">
                    {Calendar.strftime(invite.inserted_at, "%b %d")}
                  </span>
                  <button
                    phx-click="resend_invite"
                    phx-value-user-id={invite.user_id}
                    class="btn btn-xs btn-ghost gap-1"
                  >
                    <.icon name="hero-arrow-path" class="size-3" />
                    Resend
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("send_invite", %{"email" => email, "name" => name}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.org_id

    # Check if email already exists
    existing = Accounts.get_user_by_email(email)

    cond do
      existing && existing.organization_id == org_id && existing.confirmed_at != nil ->
        {:noreply, put_flash(socket, :error, "#{email} is already a member of your team")}

      existing && existing.organization_id == org_id && existing.confirmed_at == nil ->
        {:noreply, put_flash(socket, :error, "An invite is already pending for #{email}. Use the Resend button to send again.")}

      existing ->
        {:noreply, put_flash(socket, :error, "#{email} is already registered with another organization")}

      true ->
        attrs = %{
          email: email,
          name: name,
          role: "technician",
          organization_id: org_id
        }

        case Accounts.invite_user(attrs, user) do
          {:ok, {invited_user, encoded_token}} ->
            send_invite_email(invited_user, encoded_token, user, org_id)

            {:noreply,
             socket
             |> put_flash(:info, "Invite sent to #{email}")
             |> assign(:invite_form, to_form(%{"email" => "", "name" => ""}))
             |> reload_data()}

          {:error, %Ecto.Changeset{} = changeset} ->
            error_msg =
              changeset.errors
              |> Enum.map(fn
                {:email, {"has already been taken", _}} -> "This email is already in use"
                {field, {msg, _}} -> "#{field} #{msg}"
              end)
              |> Enum.join(", ")

            {:noreply, put_flash(socket, :error, error_msg)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to send invite")}
        end
    end
  end

  def handle_event("resend_invite", %{"user-id" => user_id}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.org_id

    case Accounts.resend_invite(user_id) do
      {:ok, {invited_user, encoded_token}} ->
        send_invite_email(invited_user, encoded_token, user, org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Invite resent to #{invited_user.email}")
         |> reload_data()}

      {:error, :already_confirmed} ->
        {:noreply, put_flash(socket, :error, "This user has already accepted their invite")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resend invite")}
    end
  end

  defp send_invite_email(invited_user, encoded_token, inviter, org_id) do
    org = Organizations.get_organization!(org_id)
    invite_url = url(~p"/users/invite/#{encoded_token}")

    Accounts.UserNotifier.deliver_invite_instructions(
      invited_user,
      inviter.name || inviter.email,
      org.name,
      invite_url
    )
  end

  defp reload_data(socket) do
    org_id = socket.assigns.org_id

    members = if org_id, do: Accounts.list_all_users_by_organization(org_id), else: []
    pending = if org_id, do: Accounts.list_pending_invites(org_id), else: []

    socket
    |> assign(:members, members)
    |> assign(:pending_invites, pending)
  end
end
