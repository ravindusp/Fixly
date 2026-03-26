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
      |> assign(:add_form, to_form(%{"name" => ""}))
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
          <p class="text-sm text-base-content/50">Manage contractor companies that service your properties</p>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Add contractor form -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content">Add Contractor</h3>
          </div>
          <div class="p-5">
            <.form for={@add_form} phx-submit="add_contractor" class="space-y-4">
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Company Name</label>
                <input
                  type="text"
                  name="name"
                  value={@add_form[:name].value}
                  required
                  placeholder="e.g. ABC Plumbing"
                  class="input input-bordered input-sm w-full"
                />
              </div>
              <button type="submit" class="btn btn-primary btn-sm w-full gap-1.5">
                <.icon name="hero-plus" class="size-4" />
                Add Contractor
              </button>
            </.form>
          </div>
        </div>

        <!-- Contractor list -->
        <div class="lg:col-span-2">
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
                    partnership.status == "active" && "bg-primary/10",
                    partnership.status != "active" && "bg-base-200"
                  ]}>
                    <.icon name="hero-building-storefront" class={[
                      "size-5",
                      partnership.status == "active" && "text-primary",
                      partnership.status != "active" && "text-base-content/30"
                    ]} />
                  </div>
                  <div>
                    <p class={[
                      "text-sm font-medium",
                      partnership.status == "active" && "text-base-content",
                      partnership.status != "active" && "text-base-content/50 line-through"
                    ]}>
                      {partnership.contractor_org.name}
                    </p>
                    <p class="text-xs text-base-content/50">
                      Since {Calendar.strftime(partnership.inserted_at, "%b %d, %Y")}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class={[
                    "badge badge-sm",
                    partnership.status == "active" && "badge-success",
                    partnership.status != "active" && "badge-ghost"
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
              <div :if={@partnerships == []} class="px-5 py-8 text-center text-sm text-base-content/40">
                No contractor partnerships yet. Add one to get started.
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("add_contractor", %{"name" => name}, socket) do
    org_id = socket.assigns.org_id

    case Organizations.create_contractor_org_with_partnership(%{name: name}, org_id) do
      {:ok, org} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{org.name} added as a contractor")
         |> assign(:add_form, to_form(%{"name" => ""}))
         |> reload_data()}

      {:error, changeset} ->
        error_msg =
          case changeset do
            %Ecto.Changeset{} ->
              changeset.errors
              |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
              |> Enum.join(", ")

            _ ->
              "Failed to add contractor"
          end

        {:noreply, put_flash(socket, :error, error_msg)}
    end
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

  defp reload_data(socket) do
    partnerships = Organizations.list_partnerships(socket.assigns.org_id)
    assign(socket, :partnerships, partnerships)
  end
end
