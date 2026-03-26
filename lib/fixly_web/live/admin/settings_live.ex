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
            <div class="flex flex-col sm:flex-row items-start gap-5">
              <.logo_uploader org={@org} />

              <div class="flex-1 min-w-0 space-y-4 w-full">
                <div>
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Company Name</label>
                  <input type="text" name="name" value={@form[:name].value} required class="input input-bordered input-sm w-full" />
                </div>

                <div class="flex flex-col sm:flex-row gap-4">
                  <div class="flex-1 min-w-0">
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Display Code</label>
                    <div class="flex items-center gap-2.5 h-8">
                      <code class="px-3 py-1.5 rounded-lg bg-primary/10 text-primary font-mono font-bold text-sm tracking-widest whitespace-nowrap">
                        {@org.display_code}
                      </code>
                      <span class="text-xs text-base-content/40 leading-tight">For partnerships</span>
                    </div>
                  </div>
                  <div class="flex-1 min-w-0">
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

        <!-- Main Location -->
        <.location_picker org={@org} />

        <!-- Timezone -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-globe-alt" class="size-4" />
              Timezone
            </h3>
          </div>
          <div class="p-5 space-y-4">
            <div>
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Select Timezone</label>
              <select name="timezone" class="select select-bordered select-sm w-full" phx-change="update_timezone">
                <option :for={tz <- @timezones} value={tz.id} selected={(@form[:timezone].value || "Asia/Colombo") == tz.id}>
                  {tz.label} — {tz.city}
                </option>
              </select>
            </div>
            <.timezone_clock timezone={@form[:timezone].value || "Asia/Colombo"} />
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
  # Components
  # =============================================

  attr :org, :map, required: true

  def logo_uploader(assigns) do
    ~H"""
    <div id="logo-cropper" phx-hook="LogoCropper" class="shrink-0">
      <div data-crop-trigger class="group relative w-24 h-24 rounded-2xl border-2 border-dashed border-base-300 hover:border-primary/40 flex items-center justify-center overflow-hidden bg-base-200/50 cursor-pointer transition-all">
        <img :if={@org.logo_url} src={@org.logo_url} data-crop-preview class="w-full h-full object-cover" />
        <img :if={!@org.logo_url} data-crop-preview class="w-full h-full object-cover hidden" />
        <div :if={!@org.logo_url} data-crop-placeholder class="flex flex-col items-center gap-1">
          <.icon name="hero-camera" class="size-7 text-base-content/20 group-hover:text-primary/40 transition-colors" />
        </div>
        <div class="absolute inset-0 bg-black/0 group-hover:bg-black/20 transition-colors flex items-center justify-center">
          <.icon name="hero-pencil-square" class="size-5 text-white opacity-0 group-hover:opacity-100 transition-opacity drop-shadow" />
        </div>
      </div>
      <p class="text-[10px] text-base-content/40 text-center mt-1.5 w-24">Click to upload</p>

      <input type="file" data-crop-input accept="image/jpeg,image/png,image/webp" class="hidden" />

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
            <canvas data-crop-canvas width="300" height="300" class="rounded-xl cursor-grab bg-base-200 w-full max-w-[300px] aspect-square touch-none"></canvas>
            <div class="w-full flex items-center gap-3">
              <.icon name="hero-minus" class="size-4 text-base-content/40 shrink-0" />
              <input type="range" data-crop-zoom min="0.5" max="3" step="0.05" value="1" class="range range-xs range-primary flex-1" />
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

  attr :org, :map, required: true

  def location_picker(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
      <div class="px-5 py-3.5 border-b border-base-300">
        <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
          <.icon name="hero-map-pin" class="size-4" />
          Main Location
        </h3>
      </div>
      <div id="location-picker-wrapper" phx-hook="LocationPicker" phx-update="ignore" class="p-0">
        <!-- Map -->
        <div
          data-map
          data-lat={@org.latitude}
          data-lng={@org.longitude}
          class="w-full h-72 sm:h-80 md:h-96"
          style="z-index: 0;"
        ></div>

        <!-- Address display -->
        <div class="px-5 py-3 border-t border-base-300 bg-base-200/30">
          <div class="flex items-start gap-2.5">
            <.icon name="hero-map-pin" class="size-4 text-primary mt-0.5 shrink-0" />
            <p data-location-address class="text-sm text-base-content/70 leading-relaxed">
              <%= if @org.latitude && @org.longitude do %>
                {@org.latitude}, {@org.longitude}
              <% else %>
                No location set — use the buttons below or click on the map
              <% end %>
            </p>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="grid grid-cols-2 border-t border-base-300">
          <button
            type="button"
            data-fetch-location
            class="flex items-center justify-center gap-2 px-4 py-3 text-sm font-medium text-primary hover:bg-primary/5 transition-colors border-r border-base-300"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="size-4" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
            </svg>
            Fetch My Location
          </button>
          <button
            type="button"
            data-set-on-map
            class="flex items-center justify-center gap-2 px-4 py-3 text-sm font-medium text-base-content/70 hover:bg-base-200/50 transition-colors"
          >
            <.icon name="hero-arrows-pointing-in" class="size-4" />
            Center on Pin
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :timezone, :string, required: true

  def timezone_clock(assigns) do
    ~H"""
    <div
      id="timezone-clock"
      phx-hook="TimezoneClock"
      data-timezone={@timezone}
      class="flex items-center gap-3 p-3 rounded-lg bg-base-200/50 border border-base-200"
    >
      <div class="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
        <.icon name="hero-clock" class="size-5 text-primary" />
      </div>
      <div>
        <p data-clock-time class="text-sm font-mono font-semibold text-base-content tabular-nums">--:--:--</p>
        <p data-clock-date class="text-xs text-base-content/50">Loading...</p>
      </div>
    </div>
    """
  end

  # =============================================
  # Event Handlers
  # =============================================

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("update_timezone", %{"timezone" => tz_id}, socket) do
    form_data = Map.put(socket.assigns.form.source, "timezone", tz_id)

    {:noreply,
     socket
     |> assign(:form, to_form(form_data))
     |> push_event("update_clock_timezone", %{timezone: tz_id})}
  end

  def handle_event("update_coordinates", %{"latitude" => lat, "longitude" => lng}, socket) do
    case Organizations.update_profile(socket.assigns.org, %{latitude: lat, longitude: lng}) do
      {:ok, updated_org} ->
        {:noreply, assign(socket, :org, updated_org)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save location")}
    end
  end

  def handle_event("location_error", %{"message" => msg}, socket) do
    {:noreply, put_flash(socket, :error, "Location error: #{msg}")}
  end

  def handle_event("save_cropped_logo", %{"data" => data_url}, socket) do
    # Decode base64 data URL → save to disk
    case decode_data_url(data_url) do
      {:ok, binary} ->
        upload_dir = Path.join(["priv", "static", "uploads", "logos"])
        File.mkdir_p!(upload_dir)
        filename = "#{Ecto.UUID.generate()}.png"
        dest = Path.join(upload_dir, filename)
        File.write!(dest, binary)
        logo_url = "/uploads/logos/#{filename}"

        case Organizations.update_profile(socket.assigns.org, %{logo_url: logo_url}) do
          {:ok, updated_org} ->
            {:noreply,
             socket
             |> assign(:org, updated_org)
             |> put_flash(:info, "Logo updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save logo")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid image data")}
    end
  end

  def handle_event("save", params, socket) do
    org = socket.assigns.org

    attrs = %{
      name: params["name"],
      slug: params["slug"],
      email: params["email"],
      phone: params["phone"],
      address: params["address"],
      about: params["about"],
      timezone: params["timezone"]
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

  # =============================================
  # Helpers
  # =============================================

  def decode_data_url("data:image/" <> rest) do
    case String.split(rest, ";base64,", parts: 2) do
      [_mime, b64] ->
        case Base.decode64(b64) do
          {:ok, binary} -> {:ok, binary}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  def decode_data_url(_), do: :error

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
