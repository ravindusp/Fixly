defmodule FixlyWeb.Contractor.SettingsLive do
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
        <h2 class="text-lg font-semibold text-base-content">Company Settings</h2>
        <p class="text-sm text-base-content/50">Customize your company profile — this is how property managers see you</p>
      </div>

      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
        <!-- Company Profile -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-building-storefront" class="size-4" />
              Company Profile
            </h3>
          </div>
          <div class="p-5 space-y-5">
            <div class="flex flex-col sm:flex-row items-start gap-5">
              <FixlyWeb.Admin.SettingsLive.logo_uploader org={@org} />

              <div class="flex-1 min-w-0 space-y-4 w-full">
                <div>
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Company Name</label>
                  <input type="text" name="name" value={@form[:name].value} required class="input input-bordered input-sm w-full" />
                </div>
                <div>
                  <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Your Code</label>
                  <div class="flex items-center gap-2.5 h-8">
                    <code class="px-3 py-1.5 rounded-lg bg-primary/10 text-primary font-mono font-bold text-sm tracking-widest whitespace-nowrap">
                      {@org.display_code}
                    </code>
                    <span class="text-xs text-base-content/40 leading-tight">Share with property managers</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Contact -->
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
                <input type="tel" name="phone" value={@form[:phone].value} placeholder="+94 11 234 5678" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1.5 block">Address</label>
              <textarea name="address" rows="2" placeholder="Office address" class="textarea textarea-bordered textarea-sm w-full leading-relaxed">{@form[:address].value}</textarea>
            </div>
          </div>
        </div>

        <!-- About -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-5 py-3.5 border-b border-base-300">
            <h3 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-document-text" class="size-4" />
              About Your Company
            </h3>
          </div>
          <div class="p-5">
            <textarea name="about" rows="4" placeholder="Describe your services, specializations, coverage area..." class="textarea textarea-bordered textarea-sm w-full leading-relaxed">{@form[:about].value}</textarea>
            <p class="text-xs text-base-content/40 mt-1.5">Visible to property managers who partner with you</p>
          </div>
        </div>

        <!-- Main Location -->
        <FixlyWeb.Admin.SettingsLive.location_picker org={@org} />

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
            <FixlyWeb.Admin.SettingsLive.timezone_clock timezone={@form[:timezone].value || "Asia/Colombo"} />
          </div>
        </div>

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
    case FixlyWeb.Admin.SettingsLive.decode_data_url(data_url) do
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

  defp org_to_form(org) do
    %{
      "name" => org.name || "",
      "email" => org.email || "",
      "phone" => org.phone || "",
      "address" => org.address || "",
      "about" => org.about || "",
      "timezone" => org.timezone || "Asia/Colombo"
    }
  end
end
