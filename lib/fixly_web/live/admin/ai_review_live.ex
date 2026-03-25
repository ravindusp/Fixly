defmodule FixlyWeb.Admin.AIReviewLive do
  use FixlyWeb, :live_view

  alias Fixly.AI

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    org_id = user.organization_id

    suggestions = if org_id, do: AI.list_pending_suggestions(org_id), else: []
    count = if org_id, do: AI.count_pending_suggestions(org_id), else: 0

    socket =
      socket
      |> assign(:page_title, "AI Suggestions")
      |> assign(:org_id, org_id)
      |> assign(:user, user)
      |> assign(:suggestions, suggestions)
      |> assign(:pending_count, count)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-base-content">AI Suggestions</h1>
          <span :if={@pending_count > 0} class="badge badge-primary badge-lg">{@pending_count} pending</span>
        </div>
        <button
          :if={@pending_count > 0}
          phx-click="bulk_approve"
          data-confirm="Approve all suggestions with 90%+ confidence?"
          class="btn btn-sm btn-primary gap-1.5"
        >
          <.icon name="hero-check-badge" class="size-4" />
          Approve All High Confidence
        </button>
      </div>

      <!-- Suggestion Cards -->
      <%= if @suggestions == [] do %>
        <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm">
          <div class="flex flex-col items-center justify-center py-20 text-center px-6">
            <div class="w-16 h-16 rounded-2xl bg-success/10 flex items-center justify-center mb-4">
              <.icon name="hero-sparkles" class="size-8 text-success" />
            </div>
            <h3 class="text-lg font-semibold text-base-content mb-2">No pending suggestions</h3>
            <p class="text-sm text-base-content/50 max-w-md">
              The AI hasn't generated any new suggestions that need review.
              Suggestions will appear here when the AI processes new tickets.
            </p>
          </div>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for suggestion <- @suggestions do %>
            <.suggestion_card suggestion={suggestion} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ==========================================
  # SUGGESTION CARD COMPONENT
  # ==========================================

  attr :suggestion, :map, required: true

  defp suggestion_card(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-xl border border-base-300 shadow-sm overflow-hidden">
      <div class="p-5">
        <!-- Top row: Ticket ref + Suggestion type + Confidence -->
        <div class="flex flex-wrap items-center gap-2 mb-3">
          <.link
            :if={@suggestion.ticket}
            navigate={~p"/admin/tickets/#{@suggestion.ticket.id}"}
            class="text-sm font-mono text-primary hover:underline"
          >
            {@suggestion.ticket.reference_number}
          </.link>
          <.suggestion_type_badge type={@suggestion.suggestion_type} />
          <div class="ml-auto">
            <.confidence_badge confidence={@suggestion.confidence} />
          </div>
        </div>

        <!-- Ticket description (truncated) -->
        <p :if={@suggestion.ticket} class="text-sm text-base-content/70 mb-3 line-clamp-2">
          {truncate_text(@suggestion.ticket.description, 150)}
        </p>

        <!-- Suggestion details -->
        <div class="bg-base-200/50 rounded-lg p-4 mb-3">
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-2">Suggestion</p>
          <.suggestion_detail type={@suggestion.suggestion_type} data={@suggestion.suggested_data} />
        </div>

        <!-- Reasoning -->
        <div :if={@suggestion.reasoning} class="mb-4">
          <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide mb-1">Reasoning</p>
          <p class="text-sm text-base-content/70 italic">{@suggestion.reasoning}</p>
        </div>

        <!-- Action buttons -->
        <div class="flex items-center gap-2 pt-2 border-t border-base-200">
          <button
            phx-click="approve"
            phx-value-id={@suggestion.id}
            class="btn btn-sm btn-success gap-1.5"
          >
            <.icon name="hero-check" class="size-4" />
            Approve
          </button>
          <button
            phx-click="reject"
            phx-value-id={@suggestion.id}
            class="btn btn-sm btn-ghost text-error gap-1.5"
          >
            <.icon name="hero-x-mark" class="size-4" />
            Reject
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================
  # SUB-COMPONENTS
  # ==========================================

  attr :type, :string, required: true

  defp suggestion_type_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      @type == "category" && "badge-info",
      @type == "priority" && "badge-warning",
      @type == "create_asset" && "badge-success",
      @type == "link_asset" && "badge-secondary"
    ]}>
      {format_type(@type)}
    </span>
    """
  end

  attr :confidence, :float, default: nil

  defp confidence_badge(assigns) do
    pct = if assigns.confidence, do: Float.round(assigns.confidence * 100, 0), else: 0
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="flex items-center gap-1.5">
      <div class="w-16 h-1.5 bg-base-200 rounded-full overflow-hidden">
        <div
          class={[
            "h-full rounded-full",
            @pct >= 80 && "bg-success",
            @pct >= 60 && @pct < 80 && "bg-warning",
            @pct < 60 && "bg-error"
          ]}
          style={"width: #{@pct}%"}
        >
        </div>
      </div>
      <span class={[
        "text-xs font-semibold",
        @pct >= 80 && "text-success",
        @pct >= 60 && @pct < 80 && "text-warning",
        @pct < 60 && "text-error"
      ]}>
        {trunc(@pct)}%
      </span>
    </div>
    """
  end

  attr :type, :string, required: true
  attr :data, :map, required: true

  defp suggestion_detail(assigns) do
    ~H"""
    <div class="text-sm text-base-content">
      <%= case @type do %>
        <% "category" -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Suggested category:</span>
            <span class="badge badge-primary badge-sm capitalize">{@data["category"] || @data[:category] || "unknown"}</span>
          </div>
        <% "priority" -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Suggested priority:</span>
            <span class={[
              "badge badge-sm capitalize",
              priority_badge_class(@data["priority"] || @data[:priority])
            ]}>
              {@data["priority"] || @data[:priority] || "unknown"}
            </span>
          </div>
        <% "create_asset" -> %>
          <div class="space-y-1">
            <div class="flex items-center gap-2">
              <span class="text-base-content/50">Create asset:</span>
              <span class="font-medium">{@data["name"] || @data[:name] || "Unnamed"}</span>
            </div>
            <div :if={@data["asset_type"] || @data[:asset_type]} class="flex items-center gap-2">
              <span class="text-base-content/50">Type:</span>
              <span>{@data["asset_type"] || @data[:asset_type]}</span>
            </div>
          </div>
        <% "link_asset" -> %>
          <div class="flex items-center gap-2">
            <span class="text-base-content/50">Link to asset:</span>
            <span class="font-medium">{@data["asset_name"] || @data[:asset_name] || @data["asset_id"] || @data[:asset_id] || "Unknown"}</span>
          </div>
        <% _ -> %>
          <pre class="text-xs text-base-content/60 whitespace-pre-wrap">{inspect(@data, pretty: true)}</pre>
      <% end %>
    </div>
    """
  end

  # ==========================================
  # EVENTS
  # ==========================================

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    suggestion = AI.get_suggestion!(id)

    case AI.approve_suggestion(suggestion, socket.assigns.user.id) do
      {:ok, _} ->
        {:noreply, reload(socket, "Suggestion approved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve suggestion")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    suggestion = AI.get_suggestion!(id)

    case AI.reject_suggestion(suggestion, socket.assigns.user.id) do
      {:ok, _} ->
        {:noreply, reload(socket, "Suggestion rejected")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject suggestion")}
    end
  end

  def handle_event("bulk_approve", _, socket) do
    {count, _} = AI.bulk_approve_high_confidence(socket.assigns.org_id, 0.9, socket.assigns.user.id)

    {:noreply, reload(socket, "#{count} high-confidence suggestions approved")}
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp reload(socket, flash_msg) do
    org_id = socket.assigns.org_id
    suggestions = AI.list_pending_suggestions(org_id)
    count = AI.count_pending_suggestions(org_id)

    socket
    |> assign(:suggestions, suggestions)
    |> assign(:pending_count, count)
    |> put_flash(:info, flash_msg)
  end

  defp truncate_text(nil, _), do: ""
  defp truncate_text(text, max_len) when byte_size(text) <= max_len, do: text
  defp truncate_text(text, max_len), do: String.slice(text, 0, max_len) <> "..."

  defp format_type("category"), do: "Category"
  defp format_type("priority"), do: "Priority"
  defp format_type("create_asset"), do: "Create Asset"
  defp format_type("link_asset"), do: "Link Asset"
  defp format_type(other), do: other

  defp priority_badge_class("emergency"), do: "badge-error"
  defp priority_badge_class("high"), do: "badge-warning"
  defp priority_badge_class("medium"), do: "badge-info"
  defp priority_badge_class("low"), do: "badge-ghost"
  defp priority_badge_class(_), do: "badge-ghost"
end
