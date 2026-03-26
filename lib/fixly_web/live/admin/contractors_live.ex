defmodule FixlyWeb.Admin.ContractorsLive do
  use FixlyWeb, :live_view

  alias Fixly.Organizations

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    socket =
      socket
      |> assign(:page_title, "Contractors")
      |> assign(:org_id, org_id)
      |> assign(:invite_code, "")
      |> assign(:search_results, nil)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-base-content">Contractor Partnerships</h2>
          <p class="text-sm text-base-content/50">Invite and manage contractor companies</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Invite contractor form -->
        <div class="space-y-4">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
                <.icon name="hero-link" class="size-4" />
                Invite Contractor
              </h3>
            </div>
            <div class="p-5 space-y-4">
              <p class="text-xs text-base-content/50">
                Enter a contractor's display code (e.g. FX-7K4X) or search by name
              </p>
              <form phx-submit="invite_by_code" class="space-y-3">
                <input
                  type="text"
                  name="code"
                  value={@invite_code}
                  placeholder="FX-XXXX or company name"
                  phx-change="search_contractor"
                  phx-debounce="300"
                  class="input input-bordered input-sm w-full font-mono"
                />
                <button type="submit" class="btn btn-primary btn-sm w-full gap-1.5">
                  <.icon name="hero-paper-airplane" class="size-4" />
                  Send Invite
                </button>
              </form>

              <!-- Search results -->
              <div :if={@search_results && @search_results != []} class="space-y-2">
                <p class="text-xs font-medium text-base-content/50">Found contractors:</p>
                <div
                  :for={result <- @search_results}
                  class="flex items-center justify-between p-3 rounded-lg bg-base-200/50 border border-base-200"
                >
                  <div>
                    <p class="text-sm font-medium text-base-content">{result.name}</p>
                    <p class="text-xs text-base-content/50 font-mono">{result.display_code}</p>
                  </div>
                  <button
                    phx-click="invite_org"
                    phx-value-org-id={result.id}
                    class="btn btn-xs btn-primary"
                  >
                    Invite
                  </button>
                </div>
              </div>
              <p :if={@search_results == []} class="text-xs text-base-content/40 text-center py-2">
                No contractors found
              </p>
            </div>
          </div>
        </div>

        <!-- Partnerships list -->
        <div class="lg:col-span-2">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <div class="px-5 py-3.5 border-b border-base-300">
              <h3 class="text-sm font-semibold text-base-content">
                Partnerships
                <span class="badge badge-sm badge-ghost ml-1">{length(@partnerships)}</span>
              </h3>
            </div>
            <div class="divide-y divide-base-200">
              <div :for={partnership <- @partnerships} class="px-5 py-4 flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class={[
                    "w-10 h-10 rounded-lg flex items-center justify-center",
                    partnership.status == "active" && "bg-success/10",
                    partnership.status == "pending" && "bg-warning/10",
                    partnership.status not in ["active", "pending"] && "bg-base-200"
                  ]}>
                    <.icon name="hero-building-storefront" class={[
                      "size-5",
                      partnership.status == "active" && "text-success",
                      partnership.status == "pending" && "text-warning",
                      partnership.status not in ["active", "pending"] && "text-base-content/30"
                    ]} />
                  </div>
                  <div>
                    <p class={[
                      "text-sm font-medium",
                      partnership.status == "inactive" && "text-base-content/50 line-through",
                      partnership.status != "inactive" && "text-base-content"
                    ]}>
                      {partnership.contractor_org.name}
                    </p>
                    <div class="flex items-center gap-2">
                      <span class="text-xs text-base-content/40 font-mono">
                        {partnership.contractor_org.display_code}
                      </span>
                      <span class="text-xs text-base-content/40">
                        · {Calendar.strftime(partnership.inserted_at, "%b %d, %Y")}
                      </span>
                    </div>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class={[
                    "badge badge-sm",
                    partnership.status == "active" && "badge-success",
                    partnership.status == "pending" && "badge-warning",
                    partnership.status not in ["active", "pending"] && "badge-ghost"
                  ]}>
                    {partnership.status}
                  </span>
                  <button
                    :if={partnership.status == "active"}
                    phx-click="deactivate"
                    phx-value-id={partnership.id}
                    data-confirm="Deactivate this contractor partnership?"
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>
              <div :if={@partnerships == []} class="px-5 py-12 text-center">
                <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
                  <.icon name="hero-building-storefront" class="size-6 text-base-content/30" />
                </div>
                <h3 class="text-base font-semibold text-base-content mb-1">No contractors yet</h3>
                <p class="text-sm text-base-content/50">Invite a contractor by their display code to get started.</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_contractor", %{"code" => query}, socket) when byte_size(query) >= 2 do
    results = Organizations.search_contractor_orgs(query)
    # Filter out contractors already in partnerships
    existing_ids = Enum.map(socket.assigns.partnerships, & &1.contractor_org.id)
    filtered = Enum.reject(results, &(&1.id in existing_ids))

    {:noreply, assign(socket, search_results: filtered, invite_code: query)}
  end

  def handle_event("search_contractor", %{"code" => query}, socket) do
    {:noreply, assign(socket, search_results: nil, invite_code: query)}
  end

  def handle_event("invite_by_code", %{"code" => code}, socket) do
    org_id = socket.assigns.org_id

    case Organizations.get_contractor_by_code(code) do
      nil ->
        {:noreply, put_flash(socket, :error, "No contractor found with code #{code}")}

      contractor ->
        send_invite(socket, org_id, contractor)
    end
  end

  def handle_event("invite_org", %{"org-id" => contractor_org_id}, socket) do
    send_invite(socket, socket.assigns.org_id, %{id: contractor_org_id})
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    case Organizations.deactivate_partnership(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Partnership deactivated")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to deactivate partnership")}
    end
  end

  defp send_invite(socket, owner_org_id, contractor) do
    case Organizations.send_partnership_invite(owner_org_id, contractor.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Partnership invite sent!")
         |> assign(:invite_code, "")
         |> assign(:search_results, nil)
         |> reload_data()}

      {:error, :already_active} ->
        {:noreply, put_flash(socket, :error, "Partnership already active")}

      {:error, :already_pending} ->
        {:noreply, put_flash(socket, :error, "Invite already pending")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send invite")}
    end
  end

  defp reload_data(socket) do
    org_id = socket.assigns.org_id
    partnerships = if org_id, do: Organizations.list_partnerships(org_id), else: []
    assign(socket, :partnerships, partnerships)
  end
end
