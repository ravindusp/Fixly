defmodule FixlyWeb.Layouts do
  @moduledoc "Layouts used by the application."
  use FixlyWeb, :html

  embed_templates "layouts/*"

  # --- Sidebar link component (used in app.html.heex) ---

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def sidebar_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
        @active && "bg-primary/10 text-primary",
        !@active && "text-base-content/70 hover:bg-base-200 hover:text-base-content"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      <span>{@label}</span>
    </.link>
    """
  end

  # --- Public helpers (called from templates) ---

  def initials(scope) do
    case scope do
      %{user: %{name: name}} when is_binary(name) and name != "" ->
        name
        |> String.split(" ")
        |> Enum.take(2)
        |> Enum.map(&String.first/1)
        |> Enum.join()
        |> String.upcase()

      %{user: %{email: email}} ->
        email |> String.first() |> String.upcase()

      _ ->
        "?"
    end
  end

  def user_display_name(scope) do
    case scope do
      %{user: %{name: name}} when is_binary(name) and name != "" -> name
      %{user: %{email: email}} -> email
      _ -> "User"
    end
  end

  def user_role_label(scope) do
    case scope do
      %{user: %{role: "super_admin"}} -> "Super Admin"
      %{user: %{role: "org_admin"}} -> "Admin"
      %{user: %{role: "contractor_admin"}} -> "Contractor Admin"
      %{user: %{role: "technician"}} -> "Technician"
      %{user: %{role: "resident"}} -> "Resident"
      _ -> "User"
    end
  end

  # --- Flash ---

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50 space-y-2">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Connection lost"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
