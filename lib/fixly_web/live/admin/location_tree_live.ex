defmodule FixlyWeb.Admin.LocationTreeLive do
  use FixlyWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Locations")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm p-8 text-center">
      <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center mx-auto mb-4">
        <.icon name="hero-building-office-2" class="size-7 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content mb-1">Location Tree</h3>
      <p class="text-sm text-base-content/50">Coming soon — manage your location hierarchy here.</p>
    </div>
    """
  end
end
