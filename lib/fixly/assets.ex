defmodule Fixly.Assets do
  @moduledoc "Context for managing assets and ticket-asset links."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Assets.{Asset, TicketAssetLink}
  alias Fixly.Tickets.Ticket

  # --- Paginated / DB-filtered queries ---

  @doc "Paginated asset list with DB-level filtering."
  def list_assets_paginated(org_id, filters \\ %{}, cursor \\ nil) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> apply_asset_filters(filters)
    |> preload([location: [parent: [parent: :parent]]])
    |> Fixly.Pagination.paginate_asc(cursor: cursor)
  end

  @doc "Count assets grouped by status for stat cards."
  def count_assets_by_status(org_id, filters \\ %{}) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> apply_asset_filters(filters)
    |> group_by([a], a.status)
    |> select([a], {a.status, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count assets by created_via for AI discovered stat."
  def count_assets_by_created_via(org_id) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> where([a], a.created_via != "manual")
    |> Repo.aggregate(:count, :id)
  end

  @doc "Total asset count for an org (with optional filters)."
  def count_assets(org_id, filters \\ %{}) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> apply_asset_filters(filters)
    |> Repo.aggregate(:count, :id)
  end

  defp apply_asset_filters(query, filters) when is_map(filters) do
    query
    |> maybe_asset_filter_categories(filters[:categories])
    |> maybe_asset_filter_locations(filters[:location_ids])
    |> maybe_asset_filter_statuses(filters[:statuses])
    |> maybe_asset_filter_search(filters[:search])
  end

  defp maybe_asset_filter_categories(query, nil), do: query
  defp maybe_asset_filter_categories(query, cats) do
    cats = if is_struct(cats, MapSet), do: MapSet.to_list(cats), else: cats
    if cats == [], do: query, else: where(query, [a], a.category in ^cats)
  end

  defp maybe_asset_filter_locations(query, nil), do: query
  defp maybe_asset_filter_locations(query, ids) do
    ids = if is_struct(ids, MapSet), do: MapSet.to_list(ids), else: ids
    if ids == [], do: query, else: where(query, [a], a.location_id in ^ids)
  end

  defp maybe_asset_filter_statuses(query, nil), do: query
  defp maybe_asset_filter_statuses(query, statuses) do
    statuses = if is_struct(statuses, MapSet), do: MapSet.to_list(statuses), else: statuses
    if statuses == [], do: query, else: where(query, [a], a.status in ^statuses)
  end

  defp maybe_asset_filter_search(query, nil), do: query
  defp maybe_asset_filter_search(query, ""), do: query
  defp maybe_asset_filter_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"

    query
    |> join(:left, [a], l in assoc(a, :location), as: :search_loc)
    |> where(
      [a, search_loc: l],
      ilike(a.name, ^pattern) or
        ilike(coalesce(a.category, ""), ^pattern) or
        ilike(coalesce(l.name, ""), ^pattern)
    )
  end

  # --- Assets ---

  def get_asset!(id) do
    Asset
    |> Repo.get!(id)
    |> Repo.preload([location: [parent: [parent: :parent]], organization: [], ticket_asset_links: []])
  end

  def get_asset(id), do: Repo.get(Asset, id)

  @doc "List all assets for an organization."
  def list_assets(org_id) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> order_by([a], [asc: a.name])
    |> preload([location: [parent: [parent: :parent]]])
    |> Repo.all()
  end

  @doc "List assets for a specific location."
  def list_assets_for_location(location_id) do
    Asset
    |> where([a], a.location_id == ^location_id)
    |> order_by([a], [asc: a.name])
    |> Repo.all()
  end

  @doc "Get an asset by location and name (for AI deduplication)."
  def get_asset_by_location_and_name(location_id, name) do
    Asset
    |> where([a], a.location_id == ^location_id and a.name == ^name)
    |> Repo.one()
  end

  def create_asset(attrs) do
    %Asset{}
    |> Asset.changeset(attrs)
    |> Repo.insert()
  end

  def update_asset(%Asset{} = asset, attrs) do
    asset
    |> Asset.changeset(attrs)
    |> Repo.update()
  end

  def delete_asset(%Asset{} = asset) do
    Repo.delete(asset)
  end

  # --- Ticket-Asset Links ---

  @doc "Link a ticket to an asset."
  def link_ticket_to_asset(attrs) do
    %TicketAssetLink{}
    |> TicketAssetLink.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Link a ticket to an asset by IDs with a linked_by source. Also updates asset status."
  def link_ticket_to_asset(ticket_id, asset_id, linked_by) do
    case link_ticket_to_asset(%{
      ticket_id: ticket_id,
      asset_id: asset_id,
      linked_by: linked_by
    }) do
      {:ok, link} ->
        # Auto-update asset status to needs_attention if currently operational
        asset = get_asset!(asset_id)
        if asset.status == "operational" do
          update_asset(asset, %{status: "needs_attention"})
        end
        # Update the ticket count
        update_asset_ticket_count(asset_id)
        {:ok, link}

      error ->
        error
    end
  end

  @doc "Recalculate ticket_count for an asset from actual linked tickets."
  def update_asset_ticket_count(asset_id) do
    count =
      TicketAssetLink
      |> where([l], l.asset_id == ^asset_id)
      |> Repo.aggregate(:count, :id)

    Asset
    |> where([a], a.id == ^asset_id)
    |> Repo.update_all(set: [ticket_count: count])

    :ok
  end

  @doc "Check if all linked tickets are closed/completed, and if so, restore asset to operational."
  def check_and_restore_operational(asset_id) do
    asset = get_asset!(asset_id)

    # Only restore if asset is in needs_attention or needs_repair
    if asset.status in ["needs_attention", "needs_repair"] do
      # Get all linked tickets
      linked_tickets = list_tickets_for_asset(asset_id)

      # Check if all are closed or completed
      all_resolved =
        linked_tickets != [] &&
          Enum.all?(linked_tickets, fn t -> t.status in ["closed", "completed", "reviewed"] end)

      if all_resolved do
        update_asset(asset, %{status: "operational"})
      else
        {:ok, asset}
      end
    else
      {:ok, asset}
    end
  end

  @doc "List all tickets linked to an asset."
  def list_tickets_for_asset(asset_id) do
    TicketAssetLink
    |> where([tal], tal.asset_id == ^asset_id)
    |> join(:inner, [tal], t in Ticket, on: tal.ticket_id == t.id)
    |> select([tal, t], t)
    |> preload([tal, t], [:location, :assigned_to_user, :assigned_to_org])
    |> order_by([tal, t], desc: t.inserted_at)
    |> Repo.all()
  end

  @doc "List asset links for a ticket."
  def list_links_for_ticket(ticket_id) do
    TicketAssetLink
    |> where([l], l.ticket_id == ^ticket_id)
    |> preload([:asset])
    |> Repo.all()
  end

  @doc "List asset links for an asset."
  def list_links_for_asset(asset_id) do
    TicketAssetLink
    |> where([l], l.asset_id == ^asset_id)
    |> preload([:ticket])
    |> Repo.all()
  end

  @doc "Remove a ticket-asset link."
  def unlink_ticket_from_asset(ticket_id, asset_id) do
    TicketAssetLink
    |> where([l], l.ticket_id == ^ticket_id and l.asset_id == ^asset_id)
    |> Repo.delete_all()
  end

  @doc "Get activity log for an asset (ticket comments from all linked tickets + system events)."
  def list_activity_for_asset(asset_id) do
    # Get all ticket IDs linked to this asset
    ticket_ids =
      TicketAssetLink
      |> where([l], l.asset_id == ^asset_id)
      |> select([l], l.ticket_id)
      |> Repo.all()

    if ticket_ids == [] do
      []
    else
      Fixly.Tickets.TicketComment
      |> where([c], c.ticket_id in ^ticket_ids)
      |> order_by([c], desc: c.inserted_at)
      |> preload(:user)
      |> Repo.all()
    end
  end
end
