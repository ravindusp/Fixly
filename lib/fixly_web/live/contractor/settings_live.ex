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
      |> allow_upload(:logo, accept: ~w(.jpg .jpeg .png .webp .svg), max_entries: 1, max_file_size: 5_000_000)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-4xl">
      <div>
        <h2 class="text-lg font-semibold text-base-content">Company Settings</h2>
        <p class="text-sm text-base-content/50">Customize your company profile — this is how property managers see you</p>
      </div>

      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
        <!-- Identity -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-building-storefront" class="size-4" />
              Company Profile
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
                    <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Your Code</label>
                    <div class="flex items-center gap-2">
                      <span class="badge badge-lg badge-primary font-mono font-bold tracking-wider">{@org.display_code}</span>
                      <span class="text-xs text-base-content/40">Share with property managers</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Contact -->
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
                <input type="tel" name="phone" value={@form[:phone].value} placeholder="+94 11 234 5678" class="input input-bordered input-sm w-full" />
              </div>
            </div>
            <div class="mt-4">
              <label class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-1 block">Address</label>
              <textarea name="address" rows="2" placeholder="Office address" class="textarea textarea-bordered textarea-sm w-full">{@form[:address].value}</textarea>
            </div>
          </div>
        </div>

        <!-- About -->
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="px-6 py-4 border-b border-base-300">
            <h3 class="text-base font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-document-text" class="size-4" />
              About Your Company
            </h3>
          </div>
          <div class="p-6">
            <textarea name="about" rows="4" placeholder="Describe your services, specializations, coverage area..." class="textarea textarea-bordered textarea-sm w-full">{@form[:about].value}</textarea>
            <p class="text-xs text-base-content/40 mt-1">This is visible to property managers who partner with you</p>
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
            <FixlyWeb.Admin.SettingsLive.timezone_map
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
      "email" => org.email || "",
      "phone" => org.phone || "",
      "address" => org.address || "",
      "about" => org.about || "",
      "timezone" => org.timezone || "Asia/Colombo"
    }
  end
end
