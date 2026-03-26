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
      |> allow_upload(:logo, accept: ~w(.jpg .jpeg .png .webp .svg), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-4xl">
      <div>
        <h2 class="text-lg font-semibold text-base-content">Organization Settings</h2>
        <p class="text-sm text-base-content/50">Manage your company profile and preferences</p>
      </div>

      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
        <!-- Identity card -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-building-office" class="size-4" />
              Company Identity
            </h3>
          </div>
          <div class="p-6 space-y-5">
            <div class="flex items-start gap-6">
              <!-- Logo -->
              <div class="shrink-0">
                <div class="w-20 h-20 rounded-xl border-2 border-dashed border-base-300 flex items-center justify-center overflow-hidden bg-base-200/50">
                  <%= if @org.logo_url do %>
                    <img src={@org.logo_url} class="w-full h-full object-cover rounded-xl" />
                  <% else %>
                    <.icon name="hero-camera" class="size-8 text-base-content/20" />
                  <% end %>
                </div>
                <div class="mt-2">
                  <.live_file_input upload={@uploads.logo} class="file-input file-input-bordered file-input-xs w-20" />
                </div>
                <div :for={entry <- @uploads.logo.entries} class="text-xs text-base-content/50 mt-1">
                  {entry.client_name}
                  <button type="button" phx-click="cancel_logo" phx-value-ref={entry.ref} class="text-error ml-1">&times;</button>
                </div>
              </div>

              <div class="flex-1 space-y-4">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Company Name</label>
                    <input type="text" name="name" value={@form[:name].value} required class="input input-bordered input-sm w-full" />
                  </div>
                  <div>
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Display Code</label>
                    <div class="flex items-center gap-2">
                      <span class="badge badge-lg badge-primary font-mono font-bold">{@org.display_code}</span>
                      <span class="text-xs text-base-content/40">Share this code for partnerships</span>
                    </div>
                  </div>
                </div>

                <div>
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">URL Slug</label>
                  <div class="flex items-center gap-1">
                    <span class="text-xs text-base-content/40">fixly.app/org/</span>
                    <input type="text" name="slug" value={@form[:slug].value} class="input input-bordered input-xs w-40 font-mono" placeholder="your-company" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Contact info -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-phone" class="size-4" />
              Contact Information
            </h3>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Email</label>
                <input type="email" name="email" value={@form[:email].value} placeholder="hello@company.com" class="input input-bordered input-sm w-full" />
              </div>
              <div>
                <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Phone</label>
                <input type="tel" name="phone" value={@form[:phone].value} placeholder="+1 (555) 000-0000" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div class="mt-4">
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Address</label>
              <textarea name="address" rows="2" placeholder="123 Main St, City, State, Country" class="textarea textarea-bordered textarea-sm w-full">{@form[:address].value}</textarea>
            </div>
          </div>
        </div>

        <!-- About -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-document-text" class="size-4" />
              About
            </h3>
          </div>
          <div class="p-6">
            <textarea name="about" rows="4" placeholder="Tell us about your organization..." class="textarea textarea-bordered textarea-sm w-full">{@form[:about].value}</textarea>
            <p class="text-xs text-base-content/40 mt-1">Max 2000 characters</p>
          </div>
        </div>

        <!-- Timezone -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-globe-alt" class="size-4" />
              Timezone
            </h3>
          </div>
          <div class="p-6 space-y-4">
            <.timezone_map
              selected={@form[:timezone].value || "Asia/Colombo"}
              timezones={@timezones}
            />

            <div>
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Select Timezone</label>
              <select name="timezone" class="select select-bordered select-sm w-full max-w-md" phx-change="update_timezone">
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
        <div class="flex justify-end">
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
  # Timezone Map Component
  # =============================================

  attr :selected, :string, required: true
  attr :timezones, :list, required: true

  def timezone_map(assigns) do
    selected_tz = Enum.find(assigns.timezones, fn tz -> tz.id == assigns.selected end)
    assigns = assign(assigns, :selected_tz, selected_tz)

    ~H"""
    <div class="relative rounded-xl overflow-hidden bg-[#0f1729] border border-base-300/30 p-4">
      <svg viewBox="0 0 800 400" class="w-full h-auto" xmlns="http://www.w3.org/2000/svg">
        <!-- Grid lines -->
        <defs>
          <radialGradient id="glow" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stop-color="#3b82f6" stop-opacity="0.8" />
            <stop offset="100%" stop-color="#3b82f6" stop-opacity="0" />
          </radialGradient>
        </defs>

        <!-- Subtle grid -->
        <line :for={x <- [100, 200, 300, 400, 500, 600, 700]} x1={x} y1="20" x2={x} y2="380" stroke="#1e293b" stroke-width="0.5" stroke-dasharray="2,4" />
        <line :for={y <- [80, 160, 240, 320]} x1="20" y1={y} x2="780" y2={y} stroke="#1e293b" stroke-width="0.5" stroke-dasharray="2,4" />

        <!-- Continent shapes (simplified) -->
        <!-- North America -->
        <path d="M60,68 C80,52 130,42 170,45 C200,48 230,55 255,68 C265,85 260,100 265,115 C260,128 250,138 240,148 C225,158 210,162 195,158 C170,152 145,148 120,142 C95,138 75,128 65,112 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Mexico/Central America -->
        <path d="M190,158 L205,168 L215,178 L225,190 L230,198"
              fill="none" stroke="#2563eb" stroke-opacity="0.15" stroke-width="3" stroke-linecap="round" />
        <!-- South America -->
        <path d="M235,195 C260,188 280,198 295,215 C308,235 312,258 305,278 C295,298 280,312 268,318 C258,312 252,295 250,275 C248,255 245,235 242,215 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Europe -->
        <path d="M392,58 C410,50 435,52 455,58 C468,65 475,75 470,85 C462,92 448,96 432,95 C418,94 405,90 398,82 C392,75 390,65 392,58 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Africa -->
        <path d="M425,118 C445,112 465,115 480,128 C495,145 505,168 510,195 C508,222 500,248 488,268 C472,278 455,275 442,262 C430,245 422,222 420,198 C418,172 420,145 425,118 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Asia -->
        <path d="M478,52 C520,42 565,38 610,42 C650,48 685,60 705,78 C712,95 708,110 695,120 C675,130 645,138 615,142 C585,148 555,155 530,162 C510,158 495,148 485,135 C478,118 476,98 478,78 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- India -->
        <path d="M545,148 C558,152 568,162 572,178 C575,192 568,205 558,210 C548,205 540,192 538,178 C538,165 540,155 545,148 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Southeast Asia -->
        <path d="M610,155 C625,158 638,168 635,182 C628,192 618,195 610,188 C605,178 608,165 610,155 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Japan -->
        <path d="M698,88 C708,85 715,92 712,102 C708,110 700,112 696,105 C694,98 695,92 698,88 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- Australia -->
        <path d="M678,242 C700,235 725,238 745,248 C758,260 762,278 755,292 C742,298 722,295 705,288 C688,278 680,262 678,242 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />
        <!-- New Zealand -->
        <path d="M775,272 C780,278 782,288 778,298 C774,295 772,285 775,272 Z"
              fill="#1e3a5f" fill-opacity="0.4" stroke="#2563eb" stroke-opacity="0.15" stroke-width="0.5" />

        <!-- City dots (inactive) -->
        <circle
          :for={tz <- @timezones}
          :if={tz.id != @selected}
          cx={tz.x}
          cy={tz.y}
          r="3"
          fill="#334155"
          class="cursor-pointer hover:fill-blue-400 transition-colors"
          phx-click="select_timezone"
          phx-value-tz={tz.id}
        >
          <title>{tz.label} — {tz.city}</title>
        </circle>

        <!-- Selected city (glowing) -->
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="20" fill="url(#glow)" />
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="5" fill="#3b82f6" class="animate-pulse" />
        <circle :if={@selected_tz} cx={@selected_tz.x} cy={@selected_tz.y} r="8" fill="none" stroke="#3b82f6" stroke-width="1" stroke-opacity="0.5" class="animate-ping" style="animation-duration: 2s" />

        <!-- Selected label -->
        <g :if={@selected_tz}>
          <rect
            x={label_x(@selected_tz.x) - 2}
            y={@selected_tz.y - 28}
            width={String.length("#{@selected_tz.city} · #{@selected_tz.label}") * 6 + 12}
            height="18"
            rx="4"
            fill="#1e293b"
            stroke="#3b82f6"
            stroke-width="0.5"
            stroke-opacity="0.5"
          />
          <text
            x={label_x(@selected_tz.x) + 4}
            y={@selected_tz.y - 16}
            fill="#93c5fd"
            font-size="10"
            font-family="ui-monospace, monospace"
          >
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
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

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

    # Handle logo upload
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
