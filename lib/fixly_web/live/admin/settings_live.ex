defmodule FixlyWeb.Admin.SettingsLive do
  use FixlyWeb, :live_view

  alias Fixly.Organizations
  alias Fixly.Timezones

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org = Organizations.get_organization!(user.organization_id)

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:org, org)
      |> assign(:timezones, Timezones.all())
      |> assign(:form, to_form(org_to_form(org)))
      |> allow_upload(:logo, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-3xl mx-auto">
      <div>
        <h2 class="text-lg font-semibold text-base-content">Organization Settings</h2>
        <p class="text-sm text-base-content/50">Manage your company profile and preferences</p>
      </div>

      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
        <!-- Company Profile -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-building-office" class="size-4" />
              Company Profile
            </h3>
          </div>
          <div class="p-5 space-y-5">
            <!-- Avatar + Code row -->
            <div class="flex flex-col sm:flex-row items-start gap-5">
              <.logo_uploader org={@org} uploads={@uploads} />

              <div class="flex-1 min-w-0 space-y-4 w-full">
                <div>
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Company Name</label>
                  <input type="text" name="name" value={@form[:name].value} required class="input input-bordered input-sm w-full" />
                </div>

                <div class="flex flex-col sm:flex-row gap-4">
                  <div class="flex-1">
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Display Code</label>
                    <div class="flex items-center gap-2.5 h-8">
                      <code class="px-3 py-1.5 rounded-lg bg-primary/10 text-primary font-mono font-bold text-sm tracking-widest whitespace-nowrap">
                        {@org.display_code}
                      </code>
                      <span class="text-xs text-base-content/40 leading-tight">Share for partnerships</span>
                    </div>
                  </div>
                  <div class="flex-1">
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">URL Slug</label>
                    <div class="flex items-center">
                      <span class="text-xs text-base-content/40 shrink-0 mr-1">fixly.app/</span>
                      <input type="text" name="slug" value={@form[:slug].value} class="input input-bordered input-xs font-mono flex-1 min-w-0" placeholder="your-company" />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Contact Information -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-phone" class="size-4" />
              Contact Information
            </h3>
          </div>
          <div class="p-5 space-y-4">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Email</label>
                <input type="email" name="email" value={@form[:email].value} placeholder="hello@company.com" class="input input-bordered input-sm w-full" />
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Phone</label>
                <input type="tel" name="phone" value={@form[:phone].value} placeholder="+1 (555) 000-0000" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Address</label>
              <textarea name="address" rows="2" placeholder="123 Main St, City, State, Country" class="textarea textarea-bordered textarea-sm w-full leading-relaxed">{@form[:address].value}</textarea>
            </div>
          </div>
        </div>

        <!-- About -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-document-text" class="size-4" />
              About
            </h3>
          </div>
          <div class="p-5">
            <textarea name="about" rows="4" placeholder="Tell us about your organization..." class="textarea textarea-bordered textarea-sm w-full leading-relaxed">{@form[:about].value}</textarea>
            <p class="text-xs text-base-content/40 mt-1.5">Max 2000 characters</p>
          </div>
        </div>

        <!-- Timezone -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-globe-alt" class="size-4" />
              Timezone
            </h3>
          </div>
          <div class="p-5 space-y-4">
            <.timezone_map selected={@form[:timezone].value || "Asia/Colombo"} timezones={@timezones} />
            <div>
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Select Timezone</label>
              <select name="timezone" class="select select-bordered select-sm w-full" phx-change="update_timezone">
                <option
                  :for={tz <- @timezones}
                  value={tz.id}
                  selected={(@form[:timezone].value || "Asia/Colombo") == tz.id}
                >
                  {tz.label} — {tz.city}
                </option>
              </select>
            </div>
          </div>
        </div>

        <!-- Save -->
        <div class="flex justify-end pb-4">
          <button type="submit" class="btn btn-primary gap-1.5">
            <.icon name="hero-check" class="size-4" />
            Save Changes
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # =============================================
  # Logo Uploader Component
  # =============================================

  attr :org, :map, required: true
  attr :uploads, :map, required: true

  def logo_uploader(assigns) do
    ~H"""
    <div id="logo-cropper" phx-hook="LogoCropper" class="shrink-0">
      <!-- Clickable avatar -->
      <div
        data-crop-trigger
        class="group relative w-24 h-24 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 flex items-center justify-center overflow-hidden bg-base-200/50 cursor-pointer transition-all"
      >
        <img
          :if={@org.logo_url}
          src={@org.logo_url}
          data-crop-preview
          class="w-full h-full object-cover"
        />
        <img
          :if={!@org.logo_url}
          data-crop-preview
          class="w-full h-full object-cover hidden"
        />
        <div :if={!@org.logo_url} data-crop-placeholder class="flex flex-col items-center gap-1">
          <.icon name="hero-camera" class="size-7 text-base-content/20 group-hover:text-primary/40 transition-colors" />
        </div>
        <div class="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center">
          <.icon name="hero-pencil-square" class="size-5 text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow" />
        </div>
      </div>
      <p class="text-[10px] text-base-content/40 text-center mt-1.5 w-24">Click to upload</p>

      <!-- Hidden file input for the crop modal trigger -->
      <input type="file" data-crop-input accept="image/jpeg,image/png,image/webp" class="hidden" />

      <!-- Hidden LiveView upload input -->
      <div class="hidden">
        <.live_file_input upload={@uploads.logo} />
      </div>

      <!-- Crop Modal -->
      <div data-crop-modal class="hidden fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" data-crop-cancel></div>
        <div class="relative bg-base-100 rounded-2xl shadow-2xl border border-base-300 w-full max-w-sm overflow-hidden">
          <div class="px-5 py-3.5 border-b border-base-300 flex items-center justify-between">
            <h3 class="text-sm font-semibold text-base-content">Crop Photo</h3>
            <button type="button" data-crop-cancel class="btn btn-ghost btn-xs btn-square">
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <div class="p-5 flex flex-col items-center gap-4">
            <canvas
              data-crop-canvas
              width="300"
              height="300"
              class="rounded-xl cursor-grab bg-base-200 w-full max-w-[300px] aspect-square touch-none"
            ></canvas>

            <div class="w-full flex items-center gap-3">
              <.icon name="hero-minus" class="size-4 text-base-content/40 shrink-0" />
              <input
                type="range"
                data-crop-zoom
                min="0.5"
                max="3"
                step="0.05"
                value="1"
                class="range range-xs range-primary flex-1"
              />
              <.icon name="hero-plus" class="size-4 text-base-content/40 shrink-0" />
            </div>

            <p class="text-xs text-base-content/40">Drag to reposition, slider to zoom</p>
          </div>
          <div class="px-5 py-3.5 border-t border-base-300 flex justify-end gap-2">
            <button type="button" data-crop-cancel class="btn btn-ghost btn-sm">Cancel</button>
            <button type="button" data-crop-confirm class="btn btn-primary btn-sm gap-1.5">
              <.icon name="hero-check" class="size-4" />
              Apply
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # =============================================
  # Timezone Map Component
  # =============================================

  attr :selected, :string, required: true
  attr :timezones, :list, required: true

  def timezone_map(assigns) do
    selected_tz = Enum.find(assigns.timezones, fn tz -> tz.id == assigns.selected end)
    assigns = assign(assigns, :selected_tz, selected_tz)

    ~H"""
    <div class="relative rounded-xl overflow-hidden bg-[#0f1729] border border-base-300/30 p-3 sm:p-4">
      <svg viewBox="0 0 800 400" class="w-full h-auto" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">
        <defs>
          <radialGradient id="glow" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stop-color="#3b82f6" stop-opacity="0.8" />
            <stop offset="100%" stop-color="#3b82f6" stop-opacity="0" />
          </radialGradient>
        </defs>

        <!-- Subtle grid -->
        <line :for={x <- [100, 200, 300, 400, 500, 600, 700]} x1={x} y1="20" x2={x} y2="380" stroke="#1e293b" stroke-width="0.5" stroke-dasharray="2,4" />
        <line :for={y <- [80, 160, 240, 320]} x1="20" y1={y} x2="780" y2={y} stroke="#1e293b" stroke-width="0.5" stroke-dasharray="2,4" />

        <!-- Continents -->
        <path d="M60,68 C80,52 130,42 170,45 C200,48 230,55 255,68 C265,85 260,100 265,115 C260,128 250,138 240,148 C225,158 210,162 195,158 C170,152 145,148 120,142 C95,138 75,128 65,112 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M190,158 L205,168 L215,178 L225,190 L230,198" fill="none" stroke="#2563eb" stroke-opacity="0.15" stroke-width="3" stroke-linecap="round" />
        <path d="M235,195 C260,188 280,198 295,215 C308,235 312,258 305,278 C295,298 280,312 268,318 C258,312 252,295 250,275 C248,255 245,235 242,215 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M392,58 C410,50 435,52 455,58 C468,65 475,75 470,85 C462,92 448,96 432,95 C418,94 405,90 398,82 C392,75 390,65 392,58 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M425,118 C445,112 465,115 480,128 C495,145 505,168 510,195 C508,222 500,248 488,268 C472,278 455,275 442,262 C430,245 422,222 420,198 C418,172 420,145 425,118 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M478,52 C520,42 565,38 610,42 C650,48 685,60 705,78 C712,95 708,110 695,120 C675,130 645,138 615,142 C585,148 555,155 530,162 C510,158 495,148 485,135 C478,118 476,98 478,78 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M545,148 C558,152 568,162 572,178 C575,192 568,205 558,210 C548,205 540,192 538,178 C538,165 540,155 545,148 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M610,155 C625,158 638,168 635,182 C628,192 618,195 610,188 C605,178 608,165 610,155 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M698,88 C708,85 715,92 712,102 C708,110 700,112 696,105 C694,98 695,92 698,88 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M678,242 C700,235 725,238 745,248 C758,260 762,278 755,292 C742,298 722,295 705,288 C688,278 680,262 678,242 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <path d="M775,272 C780,278 782,288 778,298 C774,295 772,285 775,272 Z" fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />

        <!-- City dots -->
        <circle :for={tz <- @timezones} :if={tz.id != @selected} cx={tz.x} cy={tz.y} r="3" fill="#334155" class="cursor-pointer hover:fill-blue-400 transition-colors" phx-click="select_timezone" phx-value-tz={tz.id}>
          <title>{tz.label} — {tz.city}</title>
        </circle>

        <!-- Selected glow -->
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="20" fill="url(#glow)" />
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="5" fill="#3b82f6" class="animate-pulse" />
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="8" fill="none" stroke="#3b82f6" stroke-width="1" stroke-opacity="0.5" class="animate-ping" style="animation-duration: 2s" />

        <!-- Label -->
        <g :if={@selected_tz}>
          <rect x={label_x(@selected_tz.x) - 2} y={@selected_tz.y - 28} width={String.length("#{@selected_tz.city} · #{@selected_tz.label}") * 6 + 12} height="18" rx="4" fill="#1e293b" stroke="#3b82f6" stroke-width="0.5" stroke-opacity="0.5" />
          <text x={label_x(@selected_tz.x) + 4} y={@selected_tz.y - 16} fill="#93c5fd" font-size="10" font-family="ui-monospace, monospace">
            {@selected_tz.city} · {@selected_tz.label}
          </text>
        </g>
      </svg>
    </div>
    """
  end

  defp label_x(x) when x > 650, do: x - 120
  defp label_x(x), do: x + 12

  # =============================================
  # Event Handlers
  # =============================================

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("select_timezone", %{"tz" => tz_id}, socket) do
    form_data = Map.put(socket.assigns.form.source, "timezone", tz_id)
    {:noreply, assign(socket, :form, to_form(form_data))}
  end

  def handle_event("update_timezone", %{"timezone" => tz_id}, socket) do
    form_data = Map.put(socket.assigns.form.source, "timezone", tz_id)
    {:noreply, assign(socket, :form, to_form(form_data))}
  end

  def handle_event("cancel_logo", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :logo, ref)}
  end

  def handle_event("save", params, socket) do
    org = socket.assigns.org

    logo_url =
      case uploaded_entries(socket, :logo) do
        {[_ | _], _} ->
          upload_dir = Path.join(["priv", "static", "uploads", "logos"])
          File.mkdir_p!(upload_dir)

          consume_uploaded_entries(socket, :logo, fn %{path: path}, entry ->
            dest = Path.join(upload_dir, "#{Ecto.UUID.generate()}_#{entry.client_name}")
            File.cp!(path, dest)
            {:ok, "/uploads/logos/#{Path.basename(dest)}"}
          end)
          |> List.first()

        _ ->
          org.logo_url
      end

    attrs = %{
      name: params["name"],
      slug: params["slug"],
      email: params["email"],
      phone: params["phone"],
      address: params["address"],
      about: params["about"],
      timezone: params["timezone"],
      logo_url: logo_url
    }

    case Organizations.update_profile(org, attrs) do
      {:ok, updated_org} ->
        {:noreply,
         socket
         |> assign(:org, updated_org)
         |> assign(:form, to_form(org_to_form(updated_org)))
         |> put_flash(:info, "Settings saved")}

      {:error, changeset} ->
        error_msg =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field} #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to save: #{error_msg}")}
    end
  end

  defp org_to_form(org) do
    %{
      "name" => org.name || "",
      "slug" => org.slug || "",
      "email" => org.email || "",
      "phone" => org.phone || "",
      "address" => org.address || "",
      "about" => org.about || "",
      "timezone" => org.timezone || "Asia/Colombo"
    }
  end
end
