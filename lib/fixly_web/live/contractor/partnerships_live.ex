defmodule FixlyWeb.Contractor.PartnershipsLive do
  use FixlyWeb, :live_view

  alias Fixly.Organizations

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id
    org = Organizations.get_organization!(org_id)

    socket =
      socket
      |> assign(:page_title, "Partnerships")
      |> assign(:org_id, org_id)
      |> assign(:org, org)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-base-content">Partnerships</h2>
          <p class="text-sm text-base-content/50">Manage your connections with property management companies</p>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-xs text-base-content/40">Your code:</span>
          <span class="badge badge-primary font-mono font-bold">{@org.display_code}</span>
        </div>
      </div>

      <!-- Pending invites -->
      <div :if={@pending_invites != []} class="bg-warning/5 rounded-xl border border-warning/20 shadow-sm">
        <div class="px-5 py-3.5 border-b border-warning/20">
          <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
            <.icon name="hero-bell-alert" class="size-4 text-warning" />
            Pending Invites
            <span class="badge badge-sm badge-warning">{length(@pending_invites)}</span>
          </h3>
        </div>
        <div class="divide-y divide-warning/10">
          <div :for={invite <- @pending_invites} class="px-5 py-4 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-lg bg-warning/10 flex items-center justify-center">
                <.icon name="hero-building-office" class="size-5 text-warning" />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content">{invite.owner_org.name}</p>
                <p class="text-xs text-base-content/50">
                  Invited {Calendar.strftime(invite.inserted_at, "%b %d, %Y")}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="accept_invite"
                phx-value-id={invite.id}
                class="btn btn-sm btn-success gap-1"
              >
                <.icon name="hero-check" class="size-4" />
                Accept
              </button>
              <button
                phx-click="decline_invite"
                phx-value-id={invite.id}
                data-confirm="Decline this partnership invite?"
                class="btn btn-sm btn-ghost text-error gap-1"
              >
                <.icon name="hero-x-mark" class="size-4" />
                Decline
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Active partnerships -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="px-5 py-3.5 border-b border-base-300">
          <h3 class="text-sm font-semibold text-base-content">
            Active Partnerships
            <span class="badge badge-sm badge-ghost ml-1">
              {Enum.count(@partnerships, &(&1.status == "active"))}
            </span>
          </h3>
        </div>
        <div class="divide-y divide-base-200">
          <div :for={partnership <- @partnerships} class="px-5 py-4 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class={[
                "w-10 h-10 rounded-lg flex items-center justify-center",
                partnership.status == "active" && "bg-success/10",
                partnership.status != "active" && "bg-base-200"
              ]}>
                <.icon name="hero-building-office" class={[
                  "size-5",
                  partnership.status == "active" && "text-success",
                  partnership.status != "active" && "text-base-content/30"
                ]} />
              </div>
              <div>
                <p class="text-sm font-medium text-base-content">{partnership.owner_org.name}</p>
                <p class="text-xs text-base-content/50">
                  Since {Calendar.strftime(partnership.inserted_at, "%b %d, %Y")}
                </p>
              </div>
            </div>
            <span class={[
              "badge badge-sm",
              partnership.status == "active" && "badge-success",
              partnership.status != "active" && "badge-ghost"
            ]}>
              {partnership.status}
            </span>
          </div>
          <div :if={@partnerships == [] && @pending_invites == []} class="px-5 py-12 text-center">
            <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
              <.icon name="hero-link" class="size-6 text-base-content/30" />
            </div>
            <h3 class="text-base font-semibold text-base-content mb-1">No partnerships yet</h3>
            <p class="text-sm text-base-content/50 max-w-sm mx-auto">
              Share your code <span class="font-mono font-bold text-primary">{@org.display_code}</span> with property managers so they can invite you.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("accept_invite", %{"id" => id}, socket) do
    case Organizations.accept_partnership(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Partnership accepted!")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to accept invite")}
    end
  end

  def handle_event("decline_invite", %{"id" => id}, socket) do
    case Organizations.decline_partnership(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invite declined")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to decline invite")}
    end
  end

  defp reload_data(socket) do
    org_id = socket.assigns.org_id
    partnerships = Organizations.list_contractor_partnerships(org_id)
    pending = Organizations.list_incoming_invites(org_id)

    socket
    |> assign(:partnerships, partnerships)
    |> assign(:pending_invites, pending)
  end
end
