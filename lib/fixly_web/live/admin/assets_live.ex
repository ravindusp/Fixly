defmodule FixlyWeb.Admin.AssetsLive do
  use FixlyWeb, :live_view

  alias Fixly.Assets
  alias Fixly.Assets.Asset
  alias Fixly.Locations
  alias Fixly.Tickets

  @categories ~w(hvac plumbing electrical structural appliance furniture it other)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    assets = if org_id, do: Assets.list_assets(org_id), else: []
    locations = if org_id, do: Locations.get_tree(org_id) |> flatten_tree(), else: []

    socket =
      socket
      |> assign(:page_title, "Assets")
      |> assign(:org_id, org_id)
      |> assign(:all_assets, assets)
      |> assign(:assets, assets)
      |> assign(:locations, locations)
      |> assign(:search_query, "")
      |> assign(:filter_category, "all")
      |> assign(:filter_location, "all")
      |> assign(:filter_status, "all")
      |> assign(:selected_asset, nil)
      |> assign(:show_add_form, false)
      |> assign(:add_form, %{name: "", category: "", location_id: ""})

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Total Assets" value={length(@all_assets)} icon="hero-cube" color="primary" />
        <.stat_card label="Operational" value={Enum.count(@all_assets, &(&1.status == "operational"))} icon="hero-check-circle" color="success" />
        <.stat_card label="Needs Repair" value={Enum.count(@all_assets, &(&1.status == "needs_repair"))} icon="hero-wrench" color="warning" />
        <.stat_card label="AI Discovered" value={Enum.count(@all_assets, &(&1.created_via in ["ai_suggested", "ai_auto"]))} icon="hero-sparkles" color="info" />
      </div>

      <div class="flex gap-6">
        <!-- Main content -->
        <div class="flex-1 min-w-0">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <!-- Toolbar -->
            <div class="px-5 py-3.5 border-b border-base-300">
              <div class="flex items-center justify-between mb-3">
                <h2 class="text-sm font-semibold text-base-content">Asset Registry</h2>
                <div class="flex items-center gap-2">
                  <form phx-change="search" class="relative">
                    <.icon name="hero-magnifying-glass" class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40" />
                    <input type="text" name="query" value={@search_query} placeholder="Search assets..." class="input input-sm input-bordered pl-9 w-52" phx-debounce="200" autocomplete="off" />
                  </form>
                  <button phx-click="toggle_add_form" class="btn btn-sm btn-primary gap-1.5">
                    <.icon name="hero-plus" class="size-4" /> Add Asset
                  </button>
                </div>
              </div>

              <!-- Filters -->
              <div class="flex items-center gap-2">
                <form phx-change="set_filter_category">
                  <select name="category" class="select select-xs select-bordered">
                    <option value="all">All Categories</option>
                    <option :for={cat <- @categories} value={cat} selected={@filter_category == cat}>{String.capitalize(cat)}</option>
                  </select>
                </form>
                <form phx-change="set_filter_location">
                  <select name="location_id" class="select select-xs select-bordered">
                    <option value="all">All Locations</option>
                    <option :for={loc <- @locations} value={loc.id} selected={@filter_location == loc.id}>
                      {String.duplicate("— ", loc.depth)}{loc.name}
                    </option>
                  </select>
                </form>
                <form phx-change="set_filter_status">
                  <select name="status" class="select select-xs select-bordered">
                    <option value="all">All Statuses</option>
                    <option :for={{val, label} <- [{"operational", "Operational"}, {"needs_repair", "Needs Repair"}, {"out_of_service", "Out of Service"}, {"decommissioned", "Decommissioned"}]} value={val} selected={@filter_status == val}>{label}</option>
                  </select>
                </form>
                <button :if={@filter_category != "all" || @filter_location != "all" || @filter_status != "all" || @search_query != ""} phx-click="clear_filters" class="btn btn-xs btn-ghost text-error gap-1">
                  <.icon name="hero-x-mark" class="size-3" /> Clear
                </button>
              </div>
            </div>

            <!-- Add form -->
            <div :if={@show_add_form} class="px-5 py-4 border-b border-base-300 bg-primary/5">
              <form phx-submit="create_asset" class="flex items-end gap-3">
                <div class="flex-1">
                  <label class="text-xs text-base-content/50 mb-1 block">Name</label>
                  <input type="text" name="name" value={@add_form.name} placeholder="e.g. AC Unit, Ceiling Fan..." class="input input-sm input-bordered w-full" autofocus />
                </div>
                <div class="w-36">
                  <label class="text-xs text-base-content/50 mb-1 block">Category</label>
                  <select name="category" class="select select-sm select-bordered w-full">
                    <option value="">Select...</option>
                    <option :for={cat <- @categories} value={cat}>{String.capitalize(cat)}</option>
                  </select>
                </div>
                <div class="w-48">
                  <label class="text-xs text-base-content/50 mb-1 block">Location</label>
                  <select name="location_id" class="select select-sm select-bordered w-full">
                    <option value="">Select...</option>
                    <option :for={loc <- @locations} value={loc.id}>
                      {String.duplicate("— ", loc.depth)}{loc.name}
                    </option>
                  </select>
                </div>
                <button type="submit" class="btn btn-sm btn-primary"><.icon name="hero-check" class="size-4" /></button>
                <button type="button" phx-click="toggle_add_form" class="btn btn-sm btn-ghost"><.icon name="hero-x-mark" class="size-4" /></button>
              </form>
            </div>

            <!-- Asset table -->
            <%= if @assets == [] do %>
              <div class="flex flex-col items-center justify-center py-16 text-center">
                <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
                  <.icon name="hero-cube" class="size-6 text-base-content/30" />
                </div>
                <h3 class="text-base font-semibold text-base-content mb-1">No assets found</h3>
                <p class="text-sm text-base-content/50">Assets are created when AI analyzes tickets, or you can add them manually.</p>
              </div>
            <% else %>
              <!-- Header -->
              <div class="grid grid-cols-[2fr_1fr_1.5fr_1fr_1fr_0.5fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
                <span>Asset</span><span>Category</span><span>Location</span><span>Status</span><span>Tickets</span><span></span>
              </div>
              <!-- Rows -->
              <div
                :for={asset <- @assets}
                phx-click="select_asset"
                phx-value-id={asset.id}
                class={[
                  "grid grid-cols-[2fr_1fr_1.5fr_1fr_1fr_0.5fr] gap-4 px-5 py-3 border-b border-base-200 items-center cursor-pointer transition-colors",
                  @selected_asset && @selected_asset.id == asset.id && "bg-primary/5 border-l-2 border-l-primary",
                  !(@selected_asset && @selected_asset.id == asset.id) && "hover:bg-base-200/30"
                ]}
              >
                <div class="flex items-center gap-3 min-w-0">
                  <div class={["w-8 h-8 rounded-lg flex items-center justify-center shrink-0", category_bg(asset.category)]}>
                    <.icon name={category_icon(asset.category)} class={["size-4", category_color(asset.category)]} />
                  </div>
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-base-content truncate">{asset.name}</p>
                    <p :if={asset.created_via != "manual"} class="text-[10px] text-accent">AI discovered</p>
                  </div>
                </div>
                <div><span class="badge badge-sm badge-ghost">{String.capitalize(asset.category || "")}</span></div>
                <div class="text-sm text-base-content/70 truncate">{if asset.location, do: asset.location.name, else: "—"}</div>
                <div><.status_pill status={asset.status} /></div>
                <div class="text-sm text-base-content/60">{asset.ticket_count}</div>
                <div></div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Detail panel -->
        <div :if={@selected_asset} class="w-full lg:w-[380px] shrink-0 bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-y-auto max-h-[calc(100vh-7rem)]">
          <div class="sticky top-0 z-10 bg-base-100 border-b border-base-300 px-5 py-3.5">
            <div class="flex items-center justify-between">
              <h3 class="text-base font-bold text-base-content">{@selected_asset.name}</h3>
              <button phx-click="deselect_asset" class="btn btn-ghost btn-xs btn-square">
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>

          <div class="p-5 space-y-4">
            <!-- Info -->
            <div class="space-y-2.5">
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Category</span><span class="badge badge-sm badge-ghost">{String.capitalize(@selected_asset.category || "—")}</span></div>
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Location</span><span class="text-base-content">{if @selected_asset.location, do: @selected_asset.location.name, else: "—"}</span></div>
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Status</span><.status_pill status={@selected_asset.status} /></div>
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Created via</span><span class={["text-sm", @selected_asset.created_via != "manual" && "text-accent"]}>{String.capitalize(@selected_asset.created_via || "manual")}</span></div>
              <div :if={@selected_asset.ai_confidence} class="flex justify-between text-sm"><span class="text-base-content/50">AI Confidence</span><span>{Float.round(@selected_asset.ai_confidence * 100, 0)}%</span></div>
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Total Tickets</span><span class="font-semibold">{@selected_asset.ticket_count}</span></div>
              <div class="flex justify-between text-sm"><span class="text-base-content/50">Repair Cost</span><span class="font-semibold">${@selected_asset.total_repair_cost || 0}</span></div>
            </div>

            <!-- Status change -->
            <div>
              <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Change Status</p>
              <div class="flex flex-wrap gap-1.5">
                <button
                  :for={{s, label} <- [{"operational", "Operational"}, {"needs_repair", "Needs Repair"}, {"out_of_service", "Out of Service"}, {"decommissioned", "Decommissioned"}]}
                  phx-click="update_asset_status"
                  phx-value-status={s}
                  class={["btn btn-xs", @selected_asset.status == s && "btn-primary", @selected_asset.status != s && "btn-ghost"]}
                >
                  {label}
                </button>
              </div>
            </div>

            <!-- Actions -->
            <div class="flex gap-2">
              <button
                phx-click="delete_asset"
                phx-value-id={@selected_asset.id}
                data-confirm={"Delete asset \"#{@selected_asset.name}\"?"}
                class="btn btn-sm btn-ghost text-error gap-1.5 flex-1"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "primary"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-base-content/60">{@label}</p>
          <p class="text-2xl font-bold text-base-content mt-1">{@value}</p>
        </div>
        <div class={["w-11 h-11 rounded-xl flex items-center justify-center", "bg-#{@color}/10"]}>
          <.icon name={@icon} class={["size-5", "text-#{@color}"]} />
        </div>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true
  defp status_pill(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm font-medium",
      @status == "operational" && "badge-success",
      @status == "needs_repair" && "badge-warning",
      @status == "out_of_service" && "badge-error",
      @status == "decommissioned" && "badge-ghost"
    ]}>{status_label(@status)}</span>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> apply_filters()}
  end

  def handle_event("set_filter_category", %{"category" => cat}, socket) do
    {:noreply, socket |> assign(:filter_category, cat) |> apply_filters()}
  end

  def handle_event("set_filter_location", %{"location_id" => loc}, socket) do
    {:noreply, socket |> assign(:filter_location, loc) |> apply_filters()}
  end

  def handle_event("set_filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter_status, status) |> apply_filters()}
  end

  def handle_event("clear_filters", _, socket) do
    {:noreply, socket |> assign(search_query: "", filter_category: "all", filter_location: "all", filter_status: "all") |> apply_filters()}
  end

  def handle_event("toggle_add_form", _, socket) do
    {:noreply, assign(socket, :show_add_form, !socket.assigns.show_add_form)}
  end

  def handle_event("create_asset", %{"name" => name, "category" => category, "location_id" => location_id}, socket) when byte_size(name) > 0 do
    attrs = %{
      name: String.trim(name),
      category: if(category == "", do: nil, else: category),
      location_id: if(location_id == "", do: nil, else: location_id),
      organization_id: socket.assigns.org_id,
      created_via: "manual"
    }

    case Assets.create_asset(attrs) do
      {:ok, asset} ->
        {:noreply, socket |> assign(show_add_form: false) |> reload_assets() |> put_flash(:info, "Asset \"#{asset.name}\" created")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create asset")}
    end
  end

  def handle_event("create_asset", _, socket), do: {:noreply, put_flash(socket, :error, "Name is required")}

  def handle_event("select_asset", %{"id" => id}, socket) do
    asset = Assets.get_asset!(id)
    {:noreply, assign(socket, :selected_asset, asset)}
  end

  def handle_event("deselect_asset", _, socket) do
    {:noreply, assign(socket, :selected_asset, nil)}
  end

  def handle_event("update_asset_status", %{"status" => status}, socket) do
    {:ok, asset} = Assets.update_asset(socket.assigns.selected_asset, %{status: status})
    asset = Assets.get_asset!(asset.id)
    {:noreply, socket |> assign(:selected_asset, asset) |> reload_assets()}
  end

  def handle_event("delete_asset", %{"id" => id}, socket) do
    asset = Assets.get_asset!(id)
    {:ok, _} = Assets.delete_asset(asset)
    {:noreply, socket |> assign(:selected_asset, nil) |> reload_assets() |> put_flash(:info, "Asset deleted")}
  end

  # --- Helpers ---

  defp reload_assets(socket) do
    assets = Assets.list_assets(socket.assigns.org_id)
    socket |> assign(:all_assets, assets) |> apply_filters()
  end

  defp apply_filters(socket) do
    filtered =
      socket.assigns.all_assets
      |> filter_by_search(socket.assigns.search_query)
      |> filter_by_category(socket.assigns.filter_category)
      |> filter_by_location(socket.assigns.filter_location)
      |> filter_by_status(socket.assigns.filter_status)

    assign(socket, :assets, filtered)
  end

  defp filter_by_search(assets, ""), do: assets
  defp filter_by_search(assets, q) do
    q = String.downcase(q)
    Enum.filter(assets, fn a ->
      String.contains?(String.downcase(a.name || ""), q) ||
        String.contains?(String.downcase(a.category || ""), q) ||
        (a.location && String.contains?(String.downcase(a.location.name || ""), q))
    end)
  end

  defp filter_by_category(assets, "all"), do: assets
  defp filter_by_category(assets, cat), do: Enum.filter(assets, &(&1.category == cat))

  defp filter_by_location(assets, "all"), do: assets
  defp filter_by_location(assets, loc_id), do: Enum.filter(assets, &(&1.location_id == loc_id))

  defp filter_by_status(assets, "all"), do: assets
  defp filter_by_status(assets, status), do: Enum.filter(assets, &(&1.status == status))

  defp flatten_tree(nodes, acc \\ []) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc ++ [node] ++ flatten_tree(node.children)
    end)
  end

  defp status_label("operational"), do: "Operational"
  defp status_label("needs_repair"), do: "Needs Repair"
  defp status_label("out_of_service"), do: "Out of Service"
  defp status_label("decommissioned"), do: "Decommissioned"
  defp status_label(other), do: String.capitalize(to_string(other))

  defp category_icon("hvac"), do: "hero-fire"
  defp category_icon("plumbing"), do: "hero-beaker"
  defp category_icon("electrical"), do: "hero-bolt"
  defp category_icon("structural"), do: "hero-home"
  defp category_icon("appliance"), do: "hero-cog-6-tooth"
  defp category_icon("furniture"), do: "hero-cube"
  defp category_icon("it"), do: "hero-computer-desktop"
  defp category_icon(_), do: "hero-wrench"

  defp category_bg("hvac"), do: "bg-red-100"
  defp category_bg("plumbing"), do: "bg-blue-100"
  defp category_bg("electrical"), do: "bg-yellow-100"
  defp category_bg("structural"), do: "bg-stone-100"
  defp category_bg("appliance"), do: "bg-purple-100"
  defp category_bg("furniture"), do: "bg-emerald-100"
  defp category_bg("it"), do: "bg-cyan-100"
  defp category_bg(_), do: "bg-base-200"

  defp category_color("hvac"), do: "text-red-600"
  defp category_color("plumbing"), do: "text-blue-600"
  defp category_color("electrical"), do: "text-yellow-600"
  defp category_color("structural"), do: "text-stone-600"
  defp category_color("appliance"), do: "text-purple-600"
  defp category_color("furniture"), do: "text-emerald-600"
  defp category_color("it"), do: "text-cyan-600"
  defp category_color(_), do: "text-base-content/50"
end
