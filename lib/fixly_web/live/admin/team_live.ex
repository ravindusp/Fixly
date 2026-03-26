defmodule FixlyWeb.Admin.TeamLive do
  use FixlyWeb, :live_view

  alias Fixly.Accounts
  alias Fixly.Organizations

  @invitable_roles ~w(org_admin technician resident)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    socket =
      socket
      |> assign(:page_title, "Team")
      |> assign(:org_id, org_id)
      |> assign(:current_user, user)
      |> assign(:invitable_roles, @invitable_roles)
      |> assign(:invite_form, to_form(%{"email" => "", "name" => "", "role" => "technician"}))
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
          <p class="text-sm text-base-content/50">Manage your organization's team members</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Invite form -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content">Invite Team Member</h3>
          </div>
          <div class="p-5">
            <.form for={@invite_form} phx-submit="send_invite" class="space-y-4">
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Name</label>
                <input type="text" name="name" value={@invite_form[:name].value} required placeholder="Full name" class="input input-bordered input-sm w-full" />
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Email</label>
                <input type="email" name="email" value={@invite_form[:email].value} required placeholder="name@company.com" class="input input-bordered input-sm w-full" />
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Role</label>
                <select name="role" class="select select-bordered select-sm w-full">
                  <option :for={role <- @invitable_roles} value={role} selected={@invite_form[:role].value == role}>
                    {role_label(role)}
                  </option>
                </select>
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
          <!-- Active members -->
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Active Members
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
                <div class="flex items-center gap-2">
                  <span class={["badge badge-sm", role_badge_class(member.role)]}>
                    {role_label(member.role)}
                  </span>
                  <button
                    :if={member.id != @current_user.id && member.role not in ["super_admin", "org_admin"]}
                    phx-click="deactivate_user"
                    phx-value-id={member.id}
                    data-confirm={"Remove #{member.name} from the team? They won't be able to log in."}
                    class="btn btn-xs btn-ghost text-error"
                  >
                    Remove
                  </button>
                </div>
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
                  <span class={["badge badge-sm badge-outline", role_badge_class(invite.role)]}>
                    {role_label(invite.role)}
                  </span>
                  <span class="text-xs text-base-content/40">{Calendar.strftime(invite.inserted_at, "%b %d")}</span>
                  <button phx-click="resend_invite" phx-value-user-id={invite.user_id} class="btn btn-xs btn-ghost gap-1">
                    <.icon name="hero-arrow-path" class="size-3" /> Resend
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Past members -->
          <div :if={@past_members != []} class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Past Members
                <span class="badge badge-sm badge-ghost ml-1">{length(@past_members)}</span>
              </h3>
            </div>
            <div class="divide-y divide-base-200">
              <div :for={member <- @past_members} class="px-5 py-3 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-full bg-base-200 flex items-center justify-center">
                    <span class="text-xs font-semibold text-base-content/40">
                      {member.name |> String.first() |> String.upcase()}
                    </span>
                  </div>
                  <div>
                    <p class="text-sm font-medium text-base-content/50">{member.name}</p>
                    <p class="text-xs text-base-content/40">{member.email}</p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-base-content/40">
                    Removed {Calendar.strftime(member.deactivated_at, "%b %d, %Y")}
                  </span>
                  <button
                    phx-click="reactivate_user"
                    phx-value-id={member.id}
                    class="btn btn-xs btn-ghost text-success gap-1"
                  >
                    <.icon name="hero-arrow-path" class="size-3" /> Reinstate
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
  def handle_event("send_invite", %{"email" => email, "name" => name, "role" => role}, socket) do
    user = socket.assigns.current_user
    org_id = socket.assigns.org_id

    existing = Accounts.get_user_by_email(email)

    cond do
      existing && existing.organization_id == org_id && existing.confirmed_at != nil ->
        {:noreply, put_flash(socket, :error, "#{email} is already a member of your team")}

      existing && existing.organization_id == org_id && existing.confirmed_at == nil ->
        {:noreply, put_flash(socket, :error, "An invite is already pending for #{email}. Use the Resend button to send again.")}

      existing ->
        {:noreply, put_flash(socket, :error, "#{email} is already registered with another organization")}

      true ->
        attrs = %{email: email, name: name, role: role, organization_id: org_id}

        case Accounts.invite_user(attrs, user) do
          {:ok, {invited_user, encoded_token}} ->
            send_invite_email(invited_user, encoded_token, user, org_id)

            {:noreply,
             socket
             |> put_flash(:info, "Invite sent to #{email}")
             |> assign(:invite_form, to_form(%{"email" => "", "name" => "", "role" => "technician"}))
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

    case Accounts.resend_invite(user_id, org_id) do
      {:ok, {invited_user, encoded_token}} ->
        send_invite_email(invited_user, encoded_token, user, org_id)
        {:noreply, socket |> put_flash(:info, "Invite resent to #{invited_user.email}") |> reload_data()}

      {:error, :already_confirmed} ->
        {:noreply, put_flash(socket, :error, "This user has already accepted their invite")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to resend invite")}
    end
  end

  def handle_event("deactivate_user", %{"id" => id}, socket) do
    case Accounts.deactivate_user(id) do
      {:ok, user} ->
        {:noreply, socket |> put_flash(:info, "#{user.name} has been removed from the team") |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove team member")}
    end
  end

  def handle_event("reactivate_user", %{"id" => id}, socket) do
    case Accounts.reactivate_user(id) do
      {:ok, user} ->
        {:noreply, socket |> put_flash(:info, "#{user.name} has been reinstated") |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reinstate team member")}
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
    past_members = if org_id, do: Accounts.list_deactivated_users_by_organization(org_id), else: []
    pending = if org_id, do: Accounts.list_pending_invites(org_id), else: []

    socket
    |> assign(:members, members)
    |> assign(:past_members, past_members)
    |> assign(:pending_invites, pending)
  end

  defp role_label("super_admin"), do: "Super Admin"
  defp role_label("org_admin"), do: "Admin"
  defp role_label("contractor_admin"), do: "Contractor Admin"
  defp role_label("technician"), do: "Technician"
  defp role_label("resident"), do: "Resident"
  defp role_label(other), do: String.capitalize(other)

  defp role_badge_class("super_admin"), do: "badge-error"
  defp role_badge_class("org_admin"), do: "badge-primary"
  defp role_badge_class("contractor_admin"), do: "badge-info"
  defp role_badge_class("technician"), do: "badge-success"
  defp role_badge_class("resident"), do: "badge-ghost"
  defp role_badge_class(_), do: "badge-ghost"
end
