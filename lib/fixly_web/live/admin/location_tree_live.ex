defmodule FixlyWeb.Admin.LocationTreeLive do
  use FixlyWeb, :live_view

  alias Fixly.Locations
  alias Fixly.Locations.Location

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    tree = if org_id, do: Locations.get_tree(org_id), else: []
    location_count = if org_id, do: Locations.count_locations(org_id), else: 0
    qr_count = if org_id, do: Locations.count_qr_codes(org_id), else: 0

    socket =
      socket
      |> assign(:page_title, "Locations")
      |> assign(:tree, tree)
      |> assign(:org_id, org_id)
      |> assign(:location_count, location_count)
      |> assign(:qr_count, qr_count)
      |> assign(:expanded, MapSet.new())
      |> assign(:selected_location, nil)
      |> assign(:show_add_form, false)
      |> assign(:add_parent_id, nil)
      |> assign(:add_name, "")
      |> assign(:add_label, "")
      |> assign(:show_edit_form, false)
      |> assign(:edit_name, "")
      |> assign(:edit_label, "")
      |> assign(:qr_svg, nil)
      |> assign(:show_qr, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats -->
      <div class="grid grid-cols-2 lg:grid-cols-3 gap-4">
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
          <p class="text-sm font-medium text-base-content/60">Total Locations</p>
          <p class="text-2xl font-bold text-base-content mt-1">{@location_count}</p>
        </div>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
          <p class="text-sm font-medium text-base-content/60">QR Codes Generated</p>
          <p class="text-2xl font-bold text-base-content mt-1">{@qr_count}</p>
        </div>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5 hidden lg:block">
          <p class="text-sm font-medium text-base-content/60">Tree Depth</p>
          <p class="text-2xl font-bold text-base-content mt-1">{max_depth(@tree)}</p>
        </div>
      </div>

      <div class="flex gap-6">
        <!-- Tree panel -->
        <div class="flex-1 min-w-0">
          <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
            <!-- Toolbar -->
            <div class="flex items-center justify-between px-5 py-3.5 border-b border-base-300">
              <h2 class="text-sm font-semibold text-base-content">Location Hierarchy</h2>
              <button phx-click="start_add_root" class="btn btn-sm btn-primary gap-1.5">
                <.icon name="hero-plus" class="size-4" />
                Add Location
              </button>
            </div>

            <!-- Add root form -->
            <div :if={@show_add_form && @add_parent_id == nil} class="px-5 py-3 border-b border-base-300 bg-primary/5">
              <.add_form add_name={@add_name} add_label={@add_label} parent_name="root level" />
            </div>

            <!-- Tree -->
            <div class="p-4">
              <%= if @tree == [] && !@show_add_form do %>
                <div class="text-center py-12">
                  <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
                    <.icon name="hero-building-office-2" class="size-6 text-base-content/30" />
                  </div>
                  <h3 class="text-base font-semibold text-base-content mb-1">No locations yet</h3>
                  <p class="text-sm text-base-content/50 mb-4">Start by adding your first building, house, or area.</p>
                  <button phx-click="start_add_root" class="btn btn-sm btn-primary gap-1.5">
                    <.icon name="hero-plus" class="size-4" /> Add First Location
                  </button>
                </div>
              <% else %>
                <div class="space-y-0.5">
                  <.tree_node
                    :for={node <- @tree}
                    node={node}
                    expanded={@expanded}
                    selected_id={@selected_location && @selected_location.id}
                    show_add_form={@show_add_form}
                    add_parent_id={@add_parent_id}
                    add_name={@add_name}
                    add_label={@add_label}
                    depth={0}
                  />
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Detail panel -->
        <.detail_panel
          :if={@selected_location}
          location={@selected_location}
          show_edit_form={@show_edit_form}
          edit_name={@edit_name}
          edit_label={@edit_label}
          qr_svg={@qr_svg}
          show_qr={@show_qr}
        />
      </div>
    </div>

    <!-- QR Download modal -->
    <dialog :if={@show_qr && @qr_svg} id="qr-modal" class="modal modal-open">
      <div class="modal-box max-w-sm text-center">
        <h3 class="text-lg font-bold mb-1">{@selected_location.name}</h3>
        <p class="text-sm text-base-content/50 mb-4">{@selected_location.label} &middot; QR Code</p>
        <div class="flex justify-center mb-4">
          <div class="bg-white p-4 rounded-xl border border-base-300 inline-block">
            {raw(@qr_svg)}
          </div>
        </div>
        <p class="text-xs text-base-content/50 mb-4 font-mono">{@selected_location.qr_code_id}</p>
        <p class="text-xs text-base-content/40 mb-4">
          URL: /r/{@selected_location.qr_code_id}
        </p>
        <div class="modal-action justify-center">
          <button phx-click="close_qr" class="btn btn-sm btn-ghost">Close</button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="close_qr">close</button>
      </form>
    </dialog>
    """
  end

  # ==========================================
  # TREE NODE (recursive)
  # ==========================================

  attr :node, :map, required: true
  attr :expanded, :any, required: true
  attr :selected_id, :string, default: nil
  attr :show_add_form, :boolean, default: false
  attr :add_parent_id, :string, default: nil
  attr :add_name, :string, default: ""
  attr :add_label, :string, default: ""
  attr :depth, :integer, default: 0

  defp tree_node(assigns) do
    has_children = assigns.node.children != []
    is_expanded = MapSet.member?(assigns.expanded, assigns.node.id)
    is_selected = assigns.selected_id == assigns.node.id
    assigns = assign(assigns, has_children: has_children, is_expanded: is_expanded, is_selected: is_selected)

    ~H"""
    <div>
      <!-- Node row -->
      <div
        class={[
          "flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer transition-colors group",
          @is_selected && "bg-primary/10",
          !@is_selected && "hover:bg-base-200/50"
        ]}
        style={"padding-left: #{@depth * 24 + 12}px"}
      >
        <!-- Expand/collapse toggle -->
        <button
          :if={@has_children}
          phx-click="toggle_expand"
          phx-value-id={@node.id}
          class="w-5 h-5 flex items-center justify-center shrink-0"
        >
          <.icon
            name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
            class="size-3.5 text-base-content/40"
          />
        </button>
        <div :if={!@has_children} class="w-5 h-5 shrink-0"></div>

        <!-- Icon -->
        <div class={[
          "w-7 h-7 rounded-lg flex items-center justify-center shrink-0",
          node_icon_bg(@node.label)
        ]}>
          <.icon name={node_icon(@node.label)} class={["size-3.5", node_icon_color(@node.label)]} />
        </div>

        <!-- Name + label -->
        <div phx-click="select_location" phx-value-id={@node.id} class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class={["text-sm font-medium truncate", @is_selected && "text-primary", !@is_selected && "text-base-content"]}>
              {@node.name}
            </span>
            <span class="text-[10px] text-base-content/40 font-medium uppercase">{@node.label}</span>
          </div>
        </div>

        <!-- QR indicator -->
        <div :if={@node.qr_code_id} class="shrink-0" title={"QR: #{@node.qr_code_id}"}>
          <.icon name="hero-qr-code" class="size-4 text-primary/50" />
        </div>

        <!-- Add child button -->
        <button
          phx-click="start_add_child"
          phx-value-id={@node.id}
          class="shrink-0 opacity-0 group-hover:opacity-100 transition-opacity btn btn-ghost btn-xs btn-square"
          title="Add child"
        >
          <.icon name="hero-plus" class="size-3.5" />
        </button>
      </div>

      <!-- Add child form (inline) -->
      <div :if={@show_add_form && @add_parent_id == @node.id} style={"padding-left: #{(@depth + 1) * 24 + 12}px"} class="py-2 pr-3">
        <.add_form add_name={@add_name} add_label={@add_label} parent_name={@node.name} />
      </div>

      <!-- Children (recursive) -->
      <div :if={@is_expanded && @has_children}>
        <.tree_node
          :for={child <- @node.children}
          node={child}
          expanded={@expanded}
          selected_id={@selected_id}
          show_add_form={@show_add_form}
          add_parent_id={@add_parent_id}
          add_name={@add_name}
          add_label={@add_label}
          depth={@depth + 1}
        />
      </div>
    </div>
    """
  end

  # ==========================================
  # ADD FORM
  # ==========================================

  defp add_form(assigns) do
    ~H"""
    <form phx-submit="create_location" class="flex items-end gap-2">
      <div class="flex-1">
        <label class="text-xs text-base-content/50 mb-1 block">Name</label>
        <input
          type="text"
          name="name"
          value={@add_name}
          placeholder={"e.g. House 4, Wing A, Room 201..."}
          class="input input-sm input-bordered w-full"
          autofocus
          phx-keydown="cancel_add"
          phx-key="Escape"
        />
      </div>
      <div class="w-32">
        <label class="text-xs text-base-content/50 mb-1 block">Type</label>
        <input
          type="text"
          name="label"
          value={@add_label}
          placeholder="House, Room..."
          class="input input-sm input-bordered w-full"
        />
      </div>
      <button type="submit" class="btn btn-sm btn-primary">
        <.icon name="hero-check" class="size-4" />
      </button>
      <button type="button" phx-click="cancel_add" class="btn btn-sm btn-ghost">
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </form>
    """
  end

  # ==========================================
  # DETAIL PANEL
  # ==========================================

  defp detail_panel(assigns) do
    ~H"""
    <div class="w-full lg:w-[360px] shrink-0 space-y-4">
      <!-- Location info -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center gap-3">
            <div class={["w-10 h-10 rounded-xl flex items-center justify-center", node_icon_bg(@location.label)]}>
              <.icon name={node_icon(@location.label)} class={["size-5", node_icon_color(@location.label)]} />
            </div>
            <div>
              <h3 class="text-base font-bold text-base-content">{@location.name}</h3>
              <p class="text-xs text-base-content/50">{@location.label} &middot; Depth {@location.depth}</p>
            </div>
          </div>
          <button phx-click="deselect_location" class="btn btn-ghost btn-xs btn-square">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <!-- Edit form -->
        <div :if={@show_edit_form}>
          <form phx-submit="update_location" class="space-y-3">
            <div>
              <label class="text-xs text-base-content/50 mb-1 block">Name</label>
              <input type="text" name="name" value={@edit_name} class="input input-sm input-bordered w-full" />
            </div>
            <div>
              <label class="text-xs text-base-content/50 mb-1 block">Type Label</label>
              <input type="text" name="label" value={@edit_label} class="input input-sm input-bordered w-full" />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="btn btn-sm btn-primary flex-1">Save</button>
              <button type="button" phx-click="cancel_edit" class="btn btn-sm btn-ghost">Cancel</button>
            </div>
          </form>
        </div>

        <!-- Actions (when not editing) -->
        <div :if={!@show_edit_form} class="space-y-2">
          <button phx-click="start_edit" class="btn btn-sm btn-ghost w-full justify-start gap-2">
            <.icon name="hero-pencil" class="size-4" /> Rename
          </button>
          <button phx-click="start_add_child" phx-value-id={@location.id} class="btn btn-sm btn-ghost w-full justify-start gap-2">
            <.icon name="hero-plus" class="size-4" /> Add Child Location
          </button>
          <button
            phx-click="delete_location"
            phx-value-id={@location.id}
            data-confirm={"Delete \"#{@location.name}\" and all its children? This cannot be undone."}
            class="btn btn-sm btn-ghost text-error w-full justify-start gap-2"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </div>

      <!-- Location Map -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-hidden">
        <div class="px-5 py-3 border-b border-base-300 flex items-center justify-between">
          <h4 class="text-sm font-semibold text-base-content flex items-center gap-2">
            <.icon name="hero-map-pin" class="size-4" />
            GPS Location
          </h4>
          <span :if={@location.metadata["gps_lat"]} class="text-[10px] font-mono text-base-content/40">
            {@location.metadata["gps_lat"]}, {@location.metadata["gps_lng"]}
          </span>
        </div>
        <div
          id={"location-map-#{@location.id}"}
          phx-hook="LocationPicker"
          phx-update="ignore"
        >
          <div
            data-map
            data-lat={@location.metadata["gps_lat"]}
            data-lng={@location.metadata["gps_lng"]}
            class="w-full h-48"
            style="z-index: 0;"
          ></div>
          <div class="grid grid-cols-2 border-t border-base-300">
            <button
              type="button"
              data-fetch-location
              class="flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-primary hover:bg-primary/5 transition-colors border-r border-base-300"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="size-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
              </svg>
              Fetch Location
            </button>
            <button
              type="button"
              data-set-on-map
              class="flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-base-content/60 hover:bg-base-200/50 transition-colors"
            >
              <.icon name="hero-arrows-pointing-in" class="size-3.5" />
              Center Pin
            </button>
          </div>
        </div>
      </div>

      <!-- QR Code section -->
      <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-5">
        <h4 class="text-sm font-semibold text-base-content mb-3">QR Code</h4>

        <div :if={@location.qr_code_id}>
          <div class="flex items-center gap-3 mb-3">
            <div class="bg-white p-2 rounded-lg border border-base-300">
              <.icon name="hero-qr-code" class="size-8 text-base-content" />
            </div>
            <div>
              <p class="text-sm font-mono text-base-content">{@location.qr_code_id}</p>
              <p class="text-xs text-base-content/50">/r/{@location.qr_code_id}</p>
            </div>
          </div>
          <button phx-click="show_qr" class="btn btn-sm btn-outline w-full gap-2">
            <.icon name="hero-qr-code" class="size-4" /> View & Download QR
          </button>
        </div>

        <div :if={!@location.qr_code_id}>
          <p class="text-sm text-base-content/50 mb-3">No QR code generated yet. Generate one to allow residents to scan and submit tickets for this location.</p>
          <button phx-click="generate_qr" class="btn btn-sm btn-primary w-full gap-2">
            <.icon name="hero-qr-code" class="size-4" /> Generate QR Code
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("select_location", %{"id" => id}, socket) do
    location = Locations.get_location!(id)
    {:noreply, assign(socket, selected_location: location, show_edit_form: false, show_qr: false, qr_svg: nil)}
  end

  def handle_event("deselect_location", _, socket) do
    {:noreply, assign(socket, selected_location: nil, show_edit_form: false, show_qr: false, qr_svg: nil)}
  end

  # --- Add location ---

  def handle_event("start_add_root", _, socket) do
    {:noreply, assign(socket, show_add_form: true, add_parent_id: nil, add_name: "", add_label: "")}
  end

  def handle_event("start_add_child", %{"id" => parent_id}, socket) do
    # Auto-expand the parent so the form is visible
    expanded = MapSet.put(socket.assigns.expanded, parent_id)
    {:noreply, assign(socket, show_add_form: true, add_parent_id: parent_id, add_name: "", add_label: "", expanded: expanded)}
  end

  def handle_event("cancel_add", _, socket) do
    {:noreply, assign(socket, show_add_form: false, add_parent_id: nil)}
  end

  def handle_event("create_location", %{"name" => name, "label" => label}, socket) when byte_size(name) > 0 do
    label = if label == "", do: "Location", else: label

    attrs = %{
      name: String.trim(name),
      label: String.trim(label),
      organization_id: socket.assigns.org_id,
      parent_id: socket.assigns.add_parent_id
    }

    case Locations.create_location(attrs) do
      {:ok, location} ->
        # Auto-expand parent and select the new location
        expanded =
          if socket.assigns.add_parent_id do
            MapSet.put(socket.assigns.expanded, socket.assigns.add_parent_id)
          else
            socket.assigns.expanded
          end

        {:noreply,
         socket
         |> assign(show_add_form: false, add_parent_id: nil, expanded: expanded, selected_location: location, show_edit_form: false)
         |> reload_tree()
         |> put_flash(:info, "\"#{location.name}\" created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create location")}
    end
  end

  def handle_event("create_location", _, socket) do
    {:noreply, put_flash(socket, :error, "Name is required")}
  end

  # --- Edit location ---

  def handle_event("start_edit", _, socket) do
    loc = socket.assigns.selected_location
    {:noreply, assign(socket, show_edit_form: true, edit_name: loc.name, edit_label: loc.label)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, show_edit_form: false)}
  end

  def handle_event("update_location", %{"name" => name, "label" => label}, socket) when byte_size(name) > 0 do
    case Locations.update_location(socket.assigns.selected_location, %{name: String.trim(name), label: String.trim(label)}) do
      {:ok, location} ->
        {:noreply,
         socket
         |> assign(selected_location: location, show_edit_form: false)
         |> reload_tree()
         |> put_flash(:info, "\"#{location.name}\" updated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update")}
    end
  end

  def handle_event("update_location", _, socket), do: {:noreply, socket}

  # --- Delete location ---

  def handle_event("delete_location", %{"id" => id}, socket) do
    location = Locations.get_location!(id)

    case Locations.delete_location(location) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(selected_location: nil, show_edit_form: false)
         |> reload_tree()
         |> put_flash(:info, "\"#{location.name}\" deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete")}
    end
  end

  # --- QR Code ---

  def handle_event("generate_qr", _, socket) do
    case Locations.generate_qr_code(socket.assigns.selected_location) do
      {:ok, location} ->
        svg = generate_qr_svg(location.qr_code_id)

        {:noreply,
         socket
         |> assign(selected_location: location, qr_svg: svg, show_qr: true)
         |> reload_tree()
         |> put_flash(:info, "QR code generated: #{location.qr_code_id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to generate QR code")}
    end
  end

  def handle_event("show_qr", _, socket) do
    svg = generate_qr_svg(socket.assigns.selected_location.qr_code_id)
    {:noreply, assign(socket, show_qr: true, qr_svg: svg)}
  end

  def handle_event("close_qr", _, socket) do
    {:noreply, assign(socket, show_qr: false)}
  end

  # --- Location GPS ---

  def handle_event("update_coordinates", %{"latitude" => lat, "longitude" => lng}, socket) do
    location = socket.assigns.selected_location
    metadata = Map.merge(location.metadata || %{}, %{"gps_lat" => lat, "gps_lng" => lng})

    case Locations.update_location(location, %{metadata: metadata}) do
      {:ok, updated} ->
        {:noreply, assign(socket, :selected_location, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save location coordinates")}
    end
  end

  def handle_event("location_error", %{"message" => msg}, socket) do
    {:noreply, put_flash(socket, :error, "Location error: #{msg}")}
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload_tree(socket) do
    tree = Locations.get_tree(socket.assigns.org_id)
    location_count = Locations.count_locations(socket.assigns.org_id)
    qr_count = Locations.count_qr_codes(socket.assigns.org_id)
    assign(socket, tree: tree, location_count: location_count, qr_count: qr_count)
  end

  defp generate_qr_svg(qr_code_id) do
    url = FixlyWeb.Endpoint.url() <> "/r/#{qr_code_id}"
    qr = EQRCode.encode(url)
    EQRCode.svg(qr, width: 200)
  end

  defp max_depth([]), do: 0
  defp max_depth(tree) do
    tree
    |> Enum.map(fn node ->
      child_depth = max_depth(node.children)
      max(node.depth, child_depth)
    end)
    |> Enum.max(fn -> 0 end)
  end

  # Node icons based on label
  defp node_icon("House"), do: "hero-home"
  defp node_icon("Building"), do: "hero-building-office-2"
  defp node_icon("Wing"), do: "hero-rectangle-group"
  defp node_icon("Floor"), do: "hero-bars-3-bottom-left"
  defp node_icon("Room"), do: "hero-square-3-stack-3d"
  defp node_icon("Lab"), do: "hero-beaker"
  defp node_icon("Facility"), do: "hero-building-storefront"
  defp node_icon("Area"), do: "hero-map"
  defp node_icon(_), do: "hero-map-pin"

  defp node_icon_bg("House"), do: "bg-blue-100"
  defp node_icon_bg("Building"), do: "bg-violet-100"
  defp node_icon_bg("Wing"), do: "bg-amber-100"
  defp node_icon_bg("Floor"), do: "bg-emerald-100"
  defp node_icon_bg("Room"), do: "bg-sky-100"
  defp node_icon_bg("Lab"), do: "bg-pink-100"
  defp node_icon_bg("Facility"), do: "bg-orange-100"
  defp node_icon_bg("Area"), do: "bg-teal-100"
  defp node_icon_bg(_), do: "bg-base-200"

  defp node_icon_color("House"), do: "text-blue-600"
  defp node_icon_color("Building"), do: "text-violet-600"
  defp node_icon_color("Wing"), do: "text-amber-600"
  defp node_icon_color("Floor"), do: "text-emerald-600"
  defp node_icon_color("Room"), do: "text-sky-600"
  defp node_icon_color("Lab"), do: "text-pink-600"
  defp node_icon_color("Facility"), do: "text-orange-600"
  defp node_icon_color("Area"), do: "text-teal-600"
  defp node_icon_color(_), do: "text-base-content/50"
end
