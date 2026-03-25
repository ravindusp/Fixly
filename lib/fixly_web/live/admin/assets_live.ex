defmodule FixlyWeb.Admin.AssetsLive do
  use FixlyWeb, :live_view

  alias Fixly.Assets
  alias Fixly.Locations

  @categories ~w(hvac plumbing electrical structural appliance furniture it other)
  @statuses [
    {"operational", "Operational"},
    {"needs_attention", "Needs Attention"},
    {"needs_repair", "Needs Repair"},
    {"out_of_service", "Out of Service"},
    {"decommissioned", "Decommissioned"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    locations = if org_id, do: Locations.get_tree(org_id) |> flatten_tree(), else: []

    socket =
      socket
      |> assign(:page_title, "Assets")
      |> assign(:org_id, org_id)
      |> assign(:locations, locations)
      |> assign(:search_query, "")
      |> assign(:filter_categories, MapSet.new())
      |> assign(:filter_location_ids, MapSet.new())
      |> assign(:filter_statuses, MapSet.new())
      |> assign(:show_category_filter, false)
      |> assign(:show_location_filter, false)
      |> assign(:show_status_filter, false)
      |> assign(:category_filter_search, "")
      |> assign(:location_filter_search, "")
      |> assign(:status_filter_search, "")
      |> assign(:categories, @categories)
      |> assign(:selected_asset, nil)
      |> assign(:show_add_form, false)
      |> assign(:add_form, %{name: "", category: "", location_id: ""})
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> reload_data()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Stats -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <.stat_card label="Total Assets" value={@stat_total} icon="hero-cube" color="primary" />
        <.stat_card label="Operational" value={@stat_operational} icon="hero-check-circle" color="success" />
        <.stat_card label="Needs Repair" value={@stat_needs_repair} icon="hero-wrench" color="warning" />
        <.stat_card label="AI Discovered" value={@stat_ai_discovered} icon="hero-sparkles" color="info" />
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
                <%!-- Category combobox --%>
                <div class="relative" phx-click-away="close_category_filter">
                  <button phx-click="toggle_category_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                    <div class="flex items-center gap-1.5 flex-1 min-w-0">
                      <span :if={MapSet.size(@filter_categories) == 0} class="text-base-content/60">All Categories</span>
                      <span :if={MapSet.size(@filter_categories) > 0} class="flex items-center gap-1">
                        <span class="badge badge-xs badge-primary">{MapSet.size(@filter_categories)}</span>
                        <span class="text-xs truncate">selected</span>
                      </span>
                    </div>
                    <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                  </button>

                  <div :if={@show_category_filter} class="absolute z-30 mt-1 w-64 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                    <div class="p-2 border-b border-base-200">
                      <form phx-change="search_category_filter">
                        <input type="text" name="query" value={@category_filter_search} placeholder="Search categories..."
                          class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                      </form>
                    </div>
                    <div class="max-h-56 overflow-y-auto p-1">
                      <button
                        :for={cat <- filtered_categories(@categories, @category_filter_search)}
                        phx-click="toggle_category_item"
                        phx-value-id={cat}
                        class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                      >
                        <div class={[
                          "w-4 h-4 rounded border flex items-center justify-center shrink-0",
                          MapSet.member?(@filter_categories, cat) && "bg-primary border-primary",
                          !MapSet.member?(@filter_categories, cat) && "border-base-300"
                        ]}>
                          <.icon :if={MapSet.member?(@filter_categories, cat)} name="hero-check" class="size-2.5 text-primary-content" />
                        </div>
                        <span class={["w-2.5 h-2.5 rounded-full shrink-0", category_dot_color(cat)]}></span>
                        <span class="text-sm">{String.capitalize(cat)}</span>
                      </button>
                    </div>
                    <div class="p-2 border-t border-base-200 flex justify-between">
                      <button phx-click="clear_category_filter" class="btn btn-xs btn-ghost">Clear</button>
                      <button phx-click="toggle_category_filter" class="btn btn-xs btn-primary">Done</button>
                    </div>
                  </div>
                </div>

                <%!-- Location combobox --%>
                <div class="relative" phx-click-away="close_location_filter">
                  <button phx-click="toggle_location_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                    <div class="flex items-center gap-1.5 flex-1 min-w-0">
                      <span :if={MapSet.size(@filter_location_ids) == 0} class="text-base-content/60">All Locations</span>
                      <span :if={MapSet.size(@filter_location_ids) > 0} class="flex items-center gap-1">
                        <span class="badge badge-xs badge-primary">{MapSet.size(@filter_location_ids)}</span>
                        <span class="text-xs truncate">selected</span>
                      </span>
                    </div>
                    <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                  </button>

                  <div :if={@show_location_filter} class="absolute z-30 mt-1 w-72 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                    <div class="p-2 border-b border-base-200">
                      <form phx-change="search_location_filter">
                        <input type="text" name="query" value={@location_filter_search} placeholder="Search locations..."
                          class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                      </form>
                    </div>
                    <div class="max-h-56 overflow-y-auto p-1">
                      <button
                        :for={loc <- filtered_locations(@locations, @location_filter_search)}
                        phx-click="toggle_location_item"
                        phx-value-id={loc.id}
                        style={"padding-left: #{loc.depth * 16 + 8}px"}
                        class="flex items-center gap-2.5 w-full pr-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                      >
                        <div class={[
                          "w-4 h-4 rounded border flex items-center justify-center shrink-0",
                          MapSet.member?(@filter_location_ids, loc.id) && "bg-primary border-primary",
                          !MapSet.member?(@filter_location_ids, loc.id) && "border-base-300"
                        ]}>
                          <.icon :if={MapSet.member?(@filter_location_ids, loc.id)} name="hero-check" class="size-2.5 text-primary-content" />
                        </div>
                        <span class={["text-sm truncate", loc.depth == 0 && "font-semibold"]}>{loc.name}</span>
                        <span :if={loc.label} class="badge badge-xs badge-ghost ml-auto shrink-0">{loc.label}</span>
                      </button>
                    </div>
                    <div class="p-2 border-t border-base-200 flex justify-between">
                      <button phx-click="clear_location_filter" class="btn btn-xs btn-ghost">Clear</button>
                      <button phx-click="toggle_location_filter" class="btn btn-xs btn-primary">Done</button>
                    </div>
                  </div>
                </div>

                <%!-- Status combobox --%>
                <div class="relative" phx-click-away="close_status_filter">
                  <button phx-click="toggle_status_filter" class="btn btn-sm btn-ghost border border-base-300 gap-1.5 min-w-[140px] justify-between">
                    <div class="flex items-center gap-1.5 flex-1 min-w-0">
                      <span :if={MapSet.size(@filter_statuses) == 0} class="text-base-content/60">All Statuses</span>
                      <span :if={MapSet.size(@filter_statuses) > 0} class="flex items-center gap-1">
                        <span class="badge badge-xs badge-primary">{MapSet.size(@filter_statuses)}</span>
                        <span class="text-xs truncate">selected</span>
                      </span>
                    </div>
                    <.icon name="hero-chevron-down" class="size-3.5 text-base-content/40 shrink-0" />
                  </button>

                  <div :if={@show_status_filter} class="absolute z-30 mt-1 w-64 bg-base-100 border border-base-300 rounded-xl shadow-xl overflow-hidden">
                    <div class="p-2 border-b border-base-200">
                      <form phx-change="search_status_filter">
                        <input type="text" name="query" value={@status_filter_search} placeholder="Search statuses..."
                          class="input input-xs input-bordered w-full" autocomplete="off" phx-debounce="150" />
                      </form>
                    </div>
                    <div class="max-h-56 overflow-y-auto p-1">
                      <button
                        :for={{val, label} <- filtered_statuses(@status_filter_search)}
                        phx-click="toggle_status_item"
                        phx-value-id={val}
                        class="flex items-center gap-2.5 w-full px-2.5 py-2 rounded-lg hover:bg-base-200 transition-colors text-left"
                      >
                        <div class={[
                          "w-4 h-4 rounded border flex items-center justify-center shrink-0",
                          MapSet.member?(@filter_statuses, val) && "bg-primary border-primary",
                          !MapSet.member?(@filter_statuses, val) && "border-base-300"
                        ]}>
                          <.icon :if={MapSet.member?(@filter_statuses, val)} name="hero-check" class="size-2.5 text-primary-content" />
                        </div>
                        <span class={["w-2.5 h-2.5 rounded-full shrink-0", status_dot_color(val)]}></span>
                        <span class="text-sm">{label}</span>
                      </button>
                    </div>
                    <div class="p-2 border-t border-base-200 flex justify-between">
                      <button phx-click="clear_status_filter" class="btn btn-xs btn-ghost">Clear</button>
                      <button phx-click="toggle_status_filter" class="btn btn-xs btn-primary">Done</button>
                    </div>
                  </div>
                </div>

                <button
                  :if={MapSet.size(@filter_categories) > 0 || MapSet.size(@filter_location_ids) > 0 || MapSet.size(@filter_statuses) > 0 || @search_query != ""}
                  phx-click="clear_filters"
                  class="btn btn-xs btn-ghost text-error gap-1"
                >
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
            <!-- Header -->
            <div class="grid grid-cols-[2fr_1fr_1.5fr_1fr_1fr_0.5fr] gap-4 px-5 py-2 border-b border-base-300 text-xs font-medium text-base-content/50 uppercase tracking-wider">
              <span>Asset</span><span>Category</span><span>Location</span><span>Status</span><span>Tickets</span><span></span>
            </div>
            <!-- Rows (streamed) -->
            <div id="assets-stream" phx-update="stream">
              <div
                :for={{dom_id, asset} <- @streams.assets}
                id={dom_id}
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
            </div>
            <!-- Empty state -->
            <div :if={@stat_total == 0} class="flex flex-col items-center justify-center py-16 text-center">
              <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
                <.icon name="hero-cube" class="size-6 text-base-content/30" />
              </div>
              <h3 class="text-base font-semibold text-base-content mb-1">No assets found</h3>
              <p class="text-sm text-base-content/50">Assets are created when AI analyzes tickets, or you can add them manually.</p>
            </div>
            <!-- Infinite scroll sentinel -->
            <div
              :if={@has_more}
              id="assets-infinite-scroll"
              phx-hook="InfiniteScroll"
              data-has-more={to_string(@has_more)}
              class="flex justify-center py-4"
            >
              <span class="loading loading-spinner loading-sm text-base-content/30"></span>
            </div>
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
                  :for={{s, label} <- [{"operational", "Operational"}, {"needs_attention", "Needs Attention"}, {"needs_repair", "Needs Repair"}, {"out_of_service", "Out of Service"}, {"decommissioned", "Decommissioned"}]}
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
              <.link
                navigate={~p"/admin/assets/#{@selected_asset.id}"}
                class="btn btn-sm btn-primary btn-outline gap-1.5 flex-1"
              >
                <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View Full Details
              </.link>
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
      @status == "needs_attention" && "badge-info",
      @status == "needs_repair" && "badge-warning",
      @status == "out_of_service" && "badge-error",
      @status == "decommissioned" && "badge-ghost"
    ]}>{status_label(@status)}</span>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more && socket.assigns.cursor do
      filters = build_asset_filters(socket.assigns)
      page = Assets.list_assets_paginated(socket.assigns.org_id, filters, socket.assigns.cursor)

      {:noreply,
       socket
       |> assign(:cursor, page.cursor)
       |> assign(:has_more, page.has_more)
       |> stream(:assets, page.entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> reload_data()}
  end

  # Category filter events
  def handle_event("toggle_category_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_category_filter, !socket.assigns.show_category_filter)
     |> assign(:show_location_filter, false)
     |> assign(:show_status_filter, false)}
  end

  def handle_event("close_category_filter", _, socket) do
    {:noreply, assign(socket, :show_category_filter, false)}
  end

  def handle_event("search_category_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :category_filter_search, query)}
  end

  def handle_event("toggle_category_item", %{"id" => cat}, socket) do
    updated =
      if MapSet.member?(socket.assigns.filter_categories, cat) do
        MapSet.delete(socket.assigns.filter_categories, cat)
      else
        MapSet.put(socket.assigns.filter_categories, cat)
      end

    {:noreply, socket |> assign(:filter_categories, updated) |> reload_data()}
  end

  def handle_event("clear_category_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:filter_categories, MapSet.new())
     |> assign(:category_filter_search, "")
     |> reload_data()}
  end

  # Location filter events
  def handle_event("toggle_location_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_location_filter, !socket.assigns.show_location_filter)
     |> assign(:show_category_filter, false)
     |> assign(:show_status_filter, false)}
  end

  def handle_event("close_location_filter", _, socket) do
    {:noreply, assign(socket, :show_location_filter, false)}
  end

  def handle_event("search_location_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :location_filter_search, query)}
  end

  def handle_event("toggle_location_item", %{"id" => id}, socket) do
    updated =
      if MapSet.member?(socket.assigns.filter_location_ids, id) do
        MapSet.delete(socket.assigns.filter_location_ids, id)
      else
        MapSet.put(socket.assigns.filter_location_ids, id)
      end

    {:noreply, socket |> assign(:filter_location_ids, updated) |> reload_data()}
  end

  def handle_event("clear_location_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:filter_location_ids, MapSet.new())
     |> assign(:location_filter_search, "")
     |> reload_data()}
  end

  # Status filter events
  def handle_event("toggle_status_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_status_filter, !socket.assigns.show_status_filter)
     |> assign(:show_category_filter, false)
     |> assign(:show_location_filter, false)}
  end

  def handle_event("close_status_filter", _, socket) do
    {:noreply, assign(socket, :show_status_filter, false)}
  end

  def handle_event("search_status_filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :status_filter_search, query)}
  end

  def handle_event("toggle_status_item", %{"id" => val}, socket) do
    updated =
      if MapSet.member?(socket.assigns.filter_statuses, val) do
        MapSet.delete(socket.assigns.filter_statuses, val)
      else
        MapSet.put(socket.assigns.filter_statuses, val)
      end

    {:noreply, socket |> assign(:filter_statuses, updated) |> reload_data()}
  end

  def handle_event("clear_status_filter", _, socket) do
    {:noreply,
     socket
     |> assign(:filter_statuses, MapSet.new())
     |> assign(:status_filter_search, "")
     |> reload_data()}
  end

  # Clear all filters
  def handle_event("clear_filters", _, socket) do
    {:noreply,
     socket
     |> assign(
       search_query: "",
       filter_categories: MapSet.new(),
       filter_location_ids: MapSet.new(),
       filter_statuses: MapSet.new(),
       category_filter_search: "",
       location_filter_search: "",
       status_filter_search: ""
     )
     |> reload_data()}
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
        {:noreply, socket |> assign(show_add_form: false) |> reload_data() |> put_flash(:info, "Asset \"#{asset.name}\" created")}
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
    {:noreply, socket |> assign(:selected_asset, asset) |> reload_data()}
  end

  def handle_event("delete_asset", %{"id" => id}, socket) do
    asset = Assets.get_asset!(id)
    {:ok, _} = Assets.delete_asset(asset)
    {:noreply, socket |> assign(:selected_asset, nil) |> reload_data() |> put_flash(:info, "Asset deleted")}
  end

  # --- Helpers ---

  defp reload_data(socket) do
    org_id = socket.assigns.org_id

    if org_id do
      filters = build_asset_filters(socket.assigns)
      page = Assets.list_assets_paginated(org_id, filters)

      # Stat cards from DB
      status_counts = Assets.count_assets_by_status(org_id, filters)
      total = status_counts |> Map.values() |> Enum.sum()
      ai_discovered = Assets.count_assets_by_created_via(org_id)

      socket
      |> assign(:stat_total, total)
      |> assign(:stat_operational, Map.get(status_counts, "operational", 0))
      |> assign(:stat_needs_repair, Map.get(status_counts, "needs_repair", 0))
      |> assign(:stat_ai_discovered, ai_discovered)
      |> assign(:cursor, page.cursor)
      |> assign(:has_more, page.has_more)
      |> stream(:assets, page.entries, reset: true)
    else
      socket
      |> assign(:stat_total, 0)
      |> assign(:stat_operational, 0)
      |> assign(:stat_needs_repair, 0)
      |> assign(:stat_ai_discovered, 0)
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> stream(:assets, [], reset: true)
    end
  end

  defp build_asset_filters(assigns) do
    filters = %{}
    filters = if MapSet.size(assigns.filter_categories) > 0, do: Map.put(filters, :categories, assigns.filter_categories), else: filters
    filters = if MapSet.size(assigns.filter_location_ids) > 0, do: Map.put(filters, :location_ids, assigns.filter_location_ids), else: filters
    filters = if MapSet.size(assigns.filter_statuses) > 0, do: Map.put(filters, :statuses, assigns.filter_statuses), else: filters
    filters = if assigns.search_query != "", do: Map.put(filters, :search, assigns.search_query), else: filters
    filters
  end

  # Filtered option lists for combobox search

  defp filtered_categories(categories, ""), do: categories
  defp filtered_categories(categories, query) do
    q = String.downcase(query)
    Enum.filter(categories, fn cat -> String.contains?(String.downcase(cat), q) end)
  end

  defp filtered_locations(locations, ""), do: locations
  defp filtered_locations(locations, query) do
    q = String.downcase(query)
    Enum.filter(locations, fn loc -> String.contains?(String.downcase(loc.name), q) end)
  end

  defp filtered_statuses("") do
    @statuses
  end
  defp filtered_statuses(query) do
    q = String.downcase(query)
    Enum.filter(@statuses, fn {_val, label} -> String.contains?(String.downcase(label), q) end)
  end

  defp flatten_tree(nodes, acc \\ []) do
    Enum.reduce(nodes, acc, fn node, acc ->
      acc ++ [node] ++ flatten_tree(node.children)
    end)
  end

  defp status_label("operational"), do: "Operational"
  defp status_label("needs_attention"), do: "Needs Attention"
  defp status_label("needs_repair"), do: "Needs Repair"
  defp status_label("out_of_service"), do: "Out of Service"
  defp status_label("decommissioned"), do: "Decommissioned"
  defp status_label(other), do: String.capitalize(to_string(other))

  # Category dot colors for combobox
  defp category_dot_color("hvac"), do: "bg-red-500"
  defp category_dot_color("plumbing"), do: "bg-blue-500"
  defp category_dot_color("electrical"), do: "bg-yellow-500"
  defp category_dot_color("structural"), do: "bg-stone-500"
  defp category_dot_color("appliance"), do: "bg-purple-500"
  defp category_dot_color("furniture"), do: "bg-emerald-500"
  defp category_dot_color("it"), do: "bg-cyan-500"
  defp category_dot_color(_), do: "bg-gray-400"

  # Status dot colors for combobox
  defp status_dot_color("operational"), do: "bg-green-500"
  defp status_dot_color("needs_attention"), do: "bg-blue-500"
  defp status_dot_color("needs_repair"), do: "bg-amber-500"
  defp status_dot_color("out_of_service"), do: "bg-red-500"
  defp status_dot_color("decommissioned"), do: "bg-gray-400"
  defp status_dot_color(_), do: "bg-gray-400"

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
