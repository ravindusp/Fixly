defmodule FixlyWeb.Super.OrganizationsLive do
  use FixlyWeb, :live_view

  alias Fixly.Organizations

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Organizations")
      |> assign(:tab, "pending")
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-lg font-semibold text-base-content">Platform Organizations</h2>
        <p class="text-sm text-base-content/50">Approve signups, manage and monitor organizations</p>
      </div>

      <!-- Stats -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
          <p class="text-xs text-base-content/50 mb-1">Pending Review</p>
          <p class="text-2xl font-bold text-warning">{Map.get(@counts, "pending", 0)}</p>
        </div>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
          <p class="text-xs text-base-content/50 mb-1">Active</p>
          <p class="text-2xl font-bold text-success">{Map.get(@counts, "active", 0)}</p>
        </div>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
          <p class="text-xs text-base-content/50 mb-1">Suspended</p>
          <p class="text-2xl font-bold text-error">{Map.get(@counts, "suspended", 0)}</p>
        </div>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-4">
          <p class="text-xs text-base-content/50 mb-1">Total</p>
          <p class="text-2xl font-bold text-base-content">
            {Enum.reduce(@counts, 0, fn {_k, v}, acc -> acc + v end)}
          </p>
        </div>
      </div>

      <!-- Tabs -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
        <div class="border-b border-base-300 px-5">
          <div class="flex gap-0">
            <button
              :for={{tab, label, count_key} <- [
                {"pending", "Pending", "pending"},
                {"active", "Active", "active"},
                {"suspended", "Suspended", "suspended"}
              ]}
              phx-click="switch_tab"
              phx-value-tab={tab}
              class={[
                "px-4 py-3 text-sm font-medium border-b-2 transition-colors",
                @tab == tab && "border-primary text-primary",
                @tab != tab && "border-transparent text-base-content/50 hover:text-base-content"
              ]}
            >
              {label}
              <span :if={Map.get(@counts, count_key, 0) > 0} class={[
                "ml-1.5 badge badge-sm",
                tab == "pending" && "badge-warning",
                tab == "active" && "badge-success",
                tab == "suspended" && "badge-error"
              ]}>
                {Map.get(@counts, count_key, 0)}
              </span>
            </button>
          </div>
        </div>

        <div class="divide-y divide-base-200">
          <div
            :for={org <- @organizations}
            class="px-5 py-4 flex items-center justify-between"
          >
            <div class="flex items-center gap-3">
              <%= if org.logo_url do %>
                <div class="w-10 h-10 rounded-lg overflow-hidden border border-base-200">
                  <img src={org.logo_url} alt={org.name} class="w-full h-full object-cover" />
                </div>
              <% else %>
                <div class={[
                  "w-10 h-10 rounded-lg flex items-center justify-center",
                  org.type == "owner" && "bg-primary/10",
                  org.type == "contractor" && "bg-warning/10"
                ]}>
                  <.icon
                    name={if org.type == "owner", do: "hero-building-office", else: "hero-wrench"}
                    class={[
                      "size-5",
                      org.type == "owner" && "text-primary",
                      org.type == "contractor" && "text-warning"
                    ]}
                  />
                </div>
              <% end %>
              <div>
                <div class="flex items-center gap-2">
                  <p class="text-sm font-medium text-base-content">{org.name}</p>
                  <span class={[
                    "badge badge-xs",
                    org.type == "owner" && "badge-primary badge-outline",
                    org.type == "contractor" && "badge-warning badge-outline"
                  ]}>
                    {org.type}
                  </span>
                </div>
                <div class="flex items-center gap-2 mt-0.5">
                  <span class="text-xs text-base-content/40 font-mono">{org.display_code}</span>
                  <span class="text-xs text-base-content/40">
                    · Registered {Calendar.strftime(org.inserted_at, "%b %d, %Y at %I:%M %p")}
                  </span>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <!-- Pending actions -->
              <button
                :if={@tab == "pending"}
                phx-click="approve"
                phx-value-id={org.id}
                class="btn btn-sm btn-success gap-1"
              >
                <.icon name="hero-check" class="size-4" />
                Approve
              </button>
              <button
                :if={@tab == "pending"}
                phx-click="reject"
                phx-value-id={org.id}
                data-confirm="Reject and delete this organization? This cannot be undone."
                class="btn btn-sm btn-outline btn-error gap-1"
              >
                <.icon name="hero-x-mark" class="size-4" />
                Reject
              </button>

              <!-- Active actions -->
              <button
                :if={@tab == "active"}
                phx-click="suspend"
                phx-value-id={org.id}
                data-confirm="Suspend this organization? Users won't be able to log in."
                class="btn btn-sm btn-outline btn-error gap-1"
              >
                <.icon name="hero-no-symbol" class="size-4" />
                Suspend
              </button>

              <!-- Suspended actions -->
              <button
                :if={@tab == "suspended"}
                phx-click="reactivate"
                phx-value-id={org.id}
                class="btn btn-sm btn-success gap-1"
              >
                <.icon name="hero-arrow-path" class="size-4" />
                Reactivate
              </button>
            </div>
          </div>

          <div :if={@organizations == []} class="px-5 py-12 text-center">
            <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
              <.icon name={tab_empty_icon(@tab)} class="size-6 text-base-content/30" />
            </div>
            <h3 class="text-base font-semibold text-base-content mb-1">{tab_empty_title(@tab)}</h3>
            <p class="text-sm text-base-content/50">{tab_empty_description(@tab)}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:tab, tab)
     |> reload_data()}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    case Organizations.approve_organization(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization approved")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    case Organizations.reject_organization(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization rejected and removed")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject")}
    end
  end

  def handle_event("suspend", %{"id" => id}, socket) do
    case Organizations.suspend_organization(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization suspended")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to suspend")}
    end
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    case Organizations.reactivate_organization(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization reactivated")
         |> reload_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reactivate")}
    end
  end

  defp reload_data(socket) do
    tab = socket.assigns.tab
    organizations = Organizations.list_organizations_by_status(tab)
    counts = Organizations.count_organizations_by_status()

    socket
    |> assign(:organizations, organizations)
    |> assign(:counts, counts)
  end

  defp tab_empty_icon("pending"), do: "hero-clock"
  defp tab_empty_icon("active"), do: "hero-building-office"
  defp tab_empty_icon("suspended"), do: "hero-no-symbol"
  defp tab_empty_icon(_), do: "hero-building-office"

  defp tab_empty_title("pending"), do: "No pending signups"
  defp tab_empty_title("active"), do: "No active organizations"
  defp tab_empty_title("suspended"), do: "No suspended organizations"
  defp tab_empty_title(_), do: "No organizations"

  defp tab_empty_description("pending"), do: "New signups will appear here for review."
  defp tab_empty_description("active"), do: "Approved organizations will appear here."
  defp tab_empty_description("suspended"), do: "Suspended organizations will appear here."
  defp tab_empty_description(_), do: ""
end
