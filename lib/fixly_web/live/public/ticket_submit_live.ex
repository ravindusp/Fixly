defmodule FixlyWeb.Public.TicketSubmitLive do
  use FixlyWeb, :live_view

  alias Fixly.Locations
  alias Fixly.Tickets

  @categories [
    {"hvac", "HVAC", "hero-fire"},
    {"plumbing", "Plumbing", "hero-beaker"},
    {"electrical", "Electrical", "hero-bolt"},
    {"structural", "Structural", "hero-home"},
    {"appliance", "Appliance", "hero-cog-6-tooth"},
    {"it", "IT", "hero-computer-desktop"},
    {"other", "Other", "hero-ellipsis-horizontal-circle"}
  ]

  # ────────────────────────────────────────────
  # Mount
  # ────────────────────────────────────────────

  @impl true
  def mount(%{"qr_code_id" => qr_code_id}, _session, socket) do
    case Locations.get_location_by_qr(qr_code_id) do
      nil ->
        socket =
          socket
          |> assign(:page_title, "Invalid QR Code")
          |> assign(:step, :error)
          |> assign(:error_message, "This QR code is not recognized. It may have been removed or is no longer active.")

        {:ok, socket}

      location ->
        children = Locations.get_children(location.id)
        ancestors = Locations.get_ancestors(location)

        # Determine if we need the user to drill down or can go straight to the form
        {step, breadcrumb} =
          if children == [] do
            {:ticket_form, ancestors ++ [location]}
          else
            {:location_select, ancestors ++ [location]}
          end

        # If the user is logged in, pre-fill submitter info
        current_scope = socket.assigns[:current_scope]

        form_defaults =
          if current_scope && current_scope.user do
            %{
              "submitter_name" => current_scope.user.name || "",
              "submitter_email" => current_scope.user.email || "",
              "submitter_phone" => ""
            }
          else
            %{
              "submitter_name" => "",
              "submitter_email" => "",
              "submitter_phone" => ""
            }
          end

        socket =
          socket
          |> assign(:page_title, "Report an Issue")
          |> assign(:step, step)
          |> assign(:qr_code_id, qr_code_id)
          |> assign(:root_location, location)
          |> assign(:current_location, location)
          |> assign(:children, children)
          |> assign(:breadcrumb, breadcrumb)
          |> assign(:categories, @categories)
          |> assign(:selected_category, nil)
          |> assign(:form_data, form_defaults)
          |> assign(:description, "")
          |> assign(:custom_item_name, "")
          |> assign(:photo_filename, nil)
          |> assign(:form_errors, %{})
          |> assign(:submitting, false)
          |> assign(:ticket_ref, nil)

        {:ok, socket}
    end
  end

  # ────────────────────────────────────────────
  # Render
  # ────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= case @step do %>
        <% :error -> %>
          <.error_view message={@error_message} />

        <% :location_select -> %>
          <.progress_steps current={1} />
          <.location_select_view
            breadcrumb={@breadcrumb}
            children={@children}
            current_location={@current_location}
          />

        <% :ticket_form -> %>
          <.progress_steps current={2} />
          <.ticket_form_view
            breadcrumb={@breadcrumb}
            categories={@categories}
            selected_category={@selected_category}
            description={@description}
            custom_item_name={@custom_item_name}
            photo_filename={@photo_filename}
            form_data={@form_data}
            form_errors={@form_errors}
            submitting={@submitting}
          />

        <% :confirmation -> %>
          <.progress_steps current={3} />
          <.confirmation_view ticket_ref={@ticket_ref} />
      <% end %>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Error View
  # ────────────────────────────────────────────

  defp error_view(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-8 text-center">
      <div class="w-16 h-16 rounded-full bg-error/10 flex items-center justify-center mx-auto mb-4">
        <.icon name="hero-exclamation-triangle" class="size-8 text-error" />
      </div>
      <h2 class="text-xl font-semibold text-base-content mb-2">QR Code Not Found</h2>
      <p class="text-sm text-base-content/60 leading-relaxed">{@message}</p>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Progress Steps
  # ────────────────────────────────────────────

  attr :current, :integer, required: true

  defp progress_steps(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-0 mb-6">
      <.step_dot number={1} label="Location" current={@current} />
      <div class={["w-12 h-0.5 mx-1", @current > 1 && "bg-primary" || "bg-base-300"]} />
      <.step_dot number={2} label="Details" current={@current} />
      <div class={["w-12 h-0.5 mx-1", @current > 2 && "bg-primary" || "bg-base-300"]} />
      <.step_dot number={3} label="Done" current={@current} />
    </div>
    """
  end

  attr :number, :integer, required: true
  attr :label, :string, required: true
  attr :current, :integer, required: true

  defp step_dot(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-1">
      <div class={[
        "w-8 h-8 rounded-full flex items-center justify-center text-sm font-semibold transition-colors",
        @number < @current && "bg-primary text-primary-content",
        @number == @current && "bg-primary text-primary-content ring-4 ring-primary/20",
        @number > @current && "bg-base-300 text-base-content/40"
      ]}>
        <%= if @number < @current do %>
          <.icon name="hero-check-mini" class="size-4" />
        <% else %>
          {@number}
        <% end %>
      </div>
      <span class={[
        "text-xs font-medium",
        @number <= @current && "text-primary",
        @number > @current && "text-base-content/40"
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Location Select View
  # ────────────────────────────────────────────

  attr :breadcrumb, :list, required: true
  attr :children, :list, required: true
  attr :current_location, :any, required: true

  defp location_select_view(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
      <div class="px-5 py-4 border-b border-base-300">
        <h2 class="text-lg font-semibold text-base-content">Select Location</h2>
        <p class="text-sm text-base-content/60 mt-0.5">
          Choose the specific area where the issue is located.
        </p>
      </div>

      <!-- Breadcrumb -->
      <.breadcrumb_bar breadcrumb={@breadcrumb} />

      <!-- Children list -->
      <div class="p-4 space-y-2">
        <button
          :for={child <- @children}
          phx-click="select_location"
          phx-value-id={child.id}
          class="w-full flex items-center gap-3 px-4 py-3 rounded-xl border border-base-300 bg-base-100 hover:bg-base-200/50 hover:border-primary/30 transition-all text-left group"
        >
          <div class="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
            <.icon name="hero-map-pin" class="size-5 text-primary" />
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-base-content group-hover:text-primary transition-colors">
              {child.name}
            </p>
            <p :if={child.label && child.label != child.name} class="text-xs text-base-content/50 mt-0.5">
              {child.label}
            </p>
          </div>
          <.icon name="hero-chevron-right-mini" class="size-5 text-base-content/30 group-hover:text-primary/60 transition-colors" />
        </button>
      </div>

      <!-- Skip / Use this location button -->
      <div class="px-5 py-4 border-t border-base-300 bg-base-200/30">
        <button
          phx-click="use_current_location"
          class="w-full btn btn-primary btn-sm gap-2"
        >
          <.icon name="hero-check-mini" class="size-4" />
          Use "{@current_location.name}" as location
        </button>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Breadcrumb Bar
  # ────────────────────────────────────────────

  attr :breadcrumb, :list, required: true

  defp breadcrumb_bar(assigns) do
    ~H"""
    <div :if={length(@breadcrumb) > 0} class="px-5 py-3 border-b border-base-200 bg-base-200/20">
      <div class="flex items-center gap-1.5 flex-wrap">
        <button
          :for={{loc, idx} <- Enum.with_index(@breadcrumb)}
          phx-click="breadcrumb_nav"
          phx-value-id={loc.id}
          phx-value-index={idx}
          class={[
            "inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium transition-colors",
            idx == length(@breadcrumb) - 1 && "bg-primary/10 text-primary",
            idx != length(@breadcrumb) - 1 && "bg-base-300/50 text-base-content/60 hover:bg-base-300 hover:text-base-content"
          ]}
        >
          <.icon :if={idx == 0} name="hero-building-office-2-mini" class="size-3" />
          {loc.name}
        </button>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Ticket Form View
  # ────────────────────────────────────────────

  attr :breadcrumb, :list, required: true
  attr :categories, :list, required: true
  attr :selected_category, :string, default: nil
  attr :description, :string, default: ""
  attr :custom_item_name, :string, default: ""
  attr :photo_filename, :string, default: nil
  attr :form_data, :map, required: true
  attr :form_errors, :map, required: true
  attr :submitting, :boolean, default: false

  defp ticket_form_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Location summary -->
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="px-5 py-3 border-b border-base-200 bg-base-200/20">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1.5 flex-wrap">
              <span
                :for={{loc, idx} <- Enum.with_index(@breadcrumb)}
                class="inline-flex items-center gap-1 text-xs font-medium"
              >
                <.icon :if={idx == 0} name="hero-map-pin-mini" class="size-3 text-primary" />
                <span :if={idx > 0} class="text-base-content/30 mx-0.5">/</span>
                <span class={idx == length(@breadcrumb) - 1 && "text-primary" || "text-base-content/60"}>
                  {loc.name}
                </span>
              </span>
            </div>
            <button phx-click="change_location" class="text-xs text-primary hover:underline">
              Change
            </button>
          </div>
        </div>
      </div>

      <!-- Main form card -->
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="px-5 py-4 border-b border-base-300">
          <h2 class="text-lg font-semibold text-base-content">Describe the Issue</h2>
          <p class="text-sm text-base-content/60 mt-0.5">
            Tell us what needs fixing so we can help you quickly.
          </p>
        </div>

        <form phx-submit="submit_ticket" phx-change="validate_form" class="p-5 space-y-5">
          <!-- Category selection -->
          <div>
            <label class="text-sm font-medium text-base-content mb-2.5 block">Category</label>
            <div class="grid grid-cols-3 sm:grid-cols-4 gap-2">
              <button
                :for={{value, label, icon} <- @categories}
                type="button"
                phx-click="select_category"
                phx-value-category={value}
                class={[
                  "flex flex-col items-center gap-1.5 px-3 py-3 rounded-xl border-2 transition-all text-center",
                  @selected_category == value && "border-primary bg-primary/5 text-primary",
                  @selected_category != value && "border-base-300 hover:border-primary/30 text-base-content/70 hover:text-base-content"
                ]}
              >
                <.icon name={icon} class="size-5" />
                <span class="text-xs font-medium">{label}</span>
              </button>
            </div>
            <p :if={@form_errors[:category]} class="text-xs text-error mt-1.5">{@form_errors[:category]}</p>
          </div>

          <!-- Custom item name (shown when "other" is selected) -->
          <div :if={@selected_category == "other"} class="animate-in fade-in slide-in-from-top-2 duration-200">
            <label for="custom_item_name" class="text-sm font-medium text-base-content mb-1.5 block">
              What type of issue?
            </label>
            <input
              type="text"
              id="custom_item_name"
              name="custom_item_name"
              value={@custom_item_name}
              placeholder="e.g. Door lock, Window, Elevator..."
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </div>

          <!-- Description -->
          <div>
            <label for="description" class="text-sm font-medium text-base-content mb-1.5 block">
              Description <span class="text-error">*</span>
            </label>
            <textarea
              id="description"
              name="description"
              rows="4"
              placeholder="Please describe the issue in detail. What is broken? When did it start? How urgent is it?"
              class={[
                "textarea textarea-bordered w-full resize-none",
                @form_errors[:description] && "textarea-error"
              ]}
              phx-debounce="300"
            >{@description}</textarea>
            <div class="flex items-center justify-between mt-1">
              <p :if={@form_errors[:description]} class="text-xs text-error">{@form_errors[:description]}</p>
              <p class="text-xs text-base-content/40 ml-auto">{String.length(@description)}/5000</p>
            </div>
          </div>

          <!-- Photo upload placeholder -->
          <div>
            <label class="text-sm font-medium text-base-content mb-1.5 block">Photo (optional)</label>
            <div class="border-2 border-dashed border-base-300 rounded-xl p-6 text-center hover:border-primary/30 transition-colors cursor-pointer">
              <.icon name="hero-camera" class="size-8 text-base-content/30 mx-auto mb-2" />
              <p class="text-sm text-base-content/50">Tap to add a photo</p>
              <p class="text-xs text-base-content/30 mt-1">Coming soon</p>
            </div>
          </div>

          <!-- Divider -->
          <div class="divider text-xs text-base-content/40">Your Contact Info</div>

          <!-- Name -->
          <div>
            <label for="submitter_name" class="text-sm font-medium text-base-content mb-1.5 block">
              Your Name
            </label>
            <input
              type="text"
              id="submitter_name"
              name="submitter_name"
              value={@form_data["submitter_name"]}
              placeholder="Full name"
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </div>

          <!-- Email -->
          <div>
            <label for="submitter_email" class="text-sm font-medium text-base-content mb-1.5 block">
              Email
            </label>
            <input
              type="email"
              id="submitter_email"
              name="submitter_email"
              value={@form_data["submitter_email"]}
              placeholder="you@example.com"
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </div>

          <!-- Phone -->
          <div>
            <label for="submitter_phone" class="text-sm font-medium text-base-content mb-1.5 block">
              Phone
            </label>
            <input
              type="tel"
              id="submitter_phone"
              name="submitter_phone"
              value={@form_data["submitter_phone"]}
              placeholder="(555) 123-4567"
              class="input input-bordered w-full"
              phx-debounce="300"
            />
          </div>

          <!-- Submit button -->
          <button
            type="submit"
            class={["btn btn-primary w-full gap-2", @submitting && "btn-disabled loading"]}
            disabled={@submitting}
          >
            <span :if={!@submitting}>
              <.icon name="hero-paper-airplane" class="size-4" />
            </span>
            <span :if={@submitting} class="loading loading-spinner loading-sm"></span>
            {if @submitting, do: "Submitting...", else: "Submit Report"}
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Confirmation View
  # ────────────────────────────────────────────

  attr :ticket_ref, :string, required: true

  defp confirmation_view(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-8 text-center">
      <!-- Green checkmark -->
      <div class="w-20 h-20 rounded-full bg-success/10 flex items-center justify-center mx-auto mb-5">
        <div class="w-14 h-14 rounded-full bg-success/20 flex items-center justify-center">
          <.icon name="hero-check" class="size-8 text-success" />
        </div>
      </div>

      <h2 class="text-xl font-semibold text-base-content mb-2">Report Submitted</h2>
      <p class="text-sm text-base-content/60 mb-6">
        Your maintenance request has been received. Our team will review it shortly.
      </p>

      <!-- Reference number card -->
      <div class="bg-base-200 rounded-xl p-4 mb-6 inline-block">
        <p class="text-xs font-medium text-base-content/50 uppercase tracking-wider mb-1">
          Reference Number
        </p>
        <p class="text-2xl font-bold text-primary font-mono tracking-wide">
          {@ticket_ref}
        </p>
      </div>

      <p class="text-xs text-base-content/40 mb-6">
        Save this reference number. You can use it to check the status of your request.
      </p>

      <!-- Actions -->
      <div class="space-y-2">
        <button phx-click="submit_another" class="btn btn-outline btn-sm w-full max-w-xs">
          <.icon name="hero-plus" class="size-4" />
          Report Another Issue
        </button>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────
  # Event Handlers
  # ────────────────────────────────────────────

  @impl true
  def handle_event("select_location", %{"id" => location_id}, socket) do
    location = Locations.get_location!(location_id)
    children = Locations.get_children(location.id)

    # Trim breadcrumb to only include ancestors up to current + this location
    breadcrumb = trim_breadcrumb(socket.assigns.breadcrumb, location)

    if children == [] do
      # Leaf node: go to ticket form
      {:noreply,
       socket
       |> assign(:step, :ticket_form)
       |> assign(:current_location, location)
       |> assign(:breadcrumb, breadcrumb)
       |> assign(:children, [])}
    else
      # Has children: show drill-down
      {:noreply,
       socket
       |> assign(:current_location, location)
       |> assign(:children, children)
       |> assign(:breadcrumb, breadcrumb)}
    end
  end

  def handle_event("use_current_location", _params, socket) do
    {:noreply, assign(socket, :step, :ticket_form)}
  end

  def handle_event("breadcrumb_nav", %{"id" => location_id, "index" => index_str}, socket) do
    {index, _} = Integer.parse(index_str)
    location = Locations.get_location!(location_id)
    children = Locations.get_children(location.id)

    # Trim breadcrumb to the clicked position
    breadcrumb = Enum.take(socket.assigns.breadcrumb, index + 1)

    if children == [] do
      {:noreply,
       socket
       |> assign(:step, :ticket_form)
       |> assign(:current_location, location)
       |> assign(:breadcrumb, breadcrumb)
       |> assign(:children, [])}
    else
      {:noreply,
       socket
       |> assign(:step, :location_select)
       |> assign(:current_location, location)
       |> assign(:children, children)
       |> assign(:breadcrumb, breadcrumb)}
    end
  end

  def handle_event("change_location", _params, socket) do
    # Go back to the root location from the QR code and restart
    root = socket.assigns.root_location
    children = Locations.get_children(root.id)
    ancestors = Locations.get_ancestors(root)
    breadcrumb = ancestors ++ [root]

    if children == [] do
      # Root has no children, stay on form
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:step, :location_select)
       |> assign(:current_location, root)
       |> assign(:children, children)
       |> assign(:breadcrumb, breadcrumb)}
    end
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    socket =
      socket
      |> assign(:selected_category, category)
      |> update(:form_errors, &Map.delete(&1, :category))

    # Clear custom_item_name when switching away from "other"
    socket =
      if category != "other" do
        assign(socket, :custom_item_name, "")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("validate_form", params, socket) do
    form_data = %{
      "submitter_name" => Map.get(params, "submitter_name", socket.assigns.form_data["submitter_name"]),
      "submitter_email" => Map.get(params, "submitter_email", socket.assigns.form_data["submitter_email"]),
      "submitter_phone" => Map.get(params, "submitter_phone", socket.assigns.form_data["submitter_phone"])
    }

    description = Map.get(params, "description", socket.assigns.description)
    custom_item_name = Map.get(params, "custom_item_name", socket.assigns.custom_item_name)

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:description, description)
     |> assign(:custom_item_name, custom_item_name)
     |> assign(:form_errors, %{})}
  end

  def handle_event("submit_ticket", params, socket) do
    description = Map.get(params, "description", socket.assigns.description) |> String.trim()
    custom_item_name = Map.get(params, "custom_item_name", socket.assigns.custom_item_name) |> String.trim()
    submitter_name = Map.get(params, "submitter_name", "") |> String.trim()
    submitter_email = Map.get(params, "submitter_email", "") |> String.trim()
    submitter_phone = Map.get(params, "submitter_phone", "") |> String.trim()

    category = socket.assigns.selected_category
    location = socket.assigns.current_location

    # Validate
    errors = %{}
    errors = if description == "" or String.length(description) < 5, do: Map.put(errors, :description, "Please describe the issue (at least 5 characters)."), else: errors

    if errors != %{} do
      {:noreply, assign(socket, :form_errors, errors)}
    else
      # Detect if logged-in user
      current_scope = socket.assigns[:current_scope]
      submitter_user_id = if current_scope && current_scope.user, do: current_scope.user.id, else: nil

      attrs = %{
        description: description,
        organization_id: location.organization_id,
        location_id: location.id,
        category: category,
        custom_item_name: if(custom_item_name != "", do: custom_item_name, else: nil),
        submitter_name: if(submitter_name != "", do: submitter_name, else: nil),
        submitter_email: if(submitter_email != "", do: submitter_email, else: nil),
        submitter_phone: if(submitter_phone != "", do: submitter_phone, else: nil),
        submitter_user_id: submitter_user_id,
        verified: submitter_user_id != nil
      }

      socket = assign(socket, :submitting, true)

      case Tickets.create_ticket(attrs) do
        {:ok, ticket} ->
          {:noreply,
           socket
           |> assign(:step, :confirmation)
           |> assign(:ticket_ref, ticket.reference_number)
           |> assign(:submitting, false)}

        {:error, changeset} ->
          error_msg =
            changeset
            |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
              Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
                opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
              end)
            end)
            |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
            |> Enum.join(". ")

          {:noreply,
           socket
           |> assign(:submitting, false)
           |> assign(:form_errors, Map.put(socket.assigns.form_errors, :submit, error_msg))
           |> put_flash(:error, "Could not submit your report. #{error_msg}")}
      end
    end
  end

  def handle_event("submit_another", _params, socket) do
    # Reset to the initial state from the QR code
    root = socket.assigns.root_location
    children = Locations.get_children(root.id)
    ancestors = Locations.get_ancestors(root)
    breadcrumb = ancestors ++ [root]

    {step, _} =
      if children == [] do
        {:ticket_form, breadcrumb}
      else
        {:location_select, breadcrumb}
      end

    {:noreply,
     socket
     |> assign(:step, step)
     |> assign(:current_location, root)
     |> assign(:children, children)
     |> assign(:breadcrumb, breadcrumb)
     |> assign(:selected_category, nil)
     |> assign(:description, "")
     |> assign(:custom_item_name, "")
     |> assign(:photo_filename, nil)
     |> assign(:form_errors, %{})
     |> assign(:submitting, false)
     |> assign(:ticket_ref, nil)
     |> clear_flash()}
  end

  # ────────────────────────────────────────────
  # Private Helpers
  # ────────────────────────────────────────────

  # Build breadcrumb by appending the selected location.
  # If the location is already in the breadcrumb, trim to that point.
  defp trim_breadcrumb(breadcrumb, location) do
    case Enum.find_index(breadcrumb, &(&1.id == location.id)) do
      nil -> breadcrumb ++ [location]
      idx -> Enum.take(breadcrumb, idx + 1)
    end
  end
end
