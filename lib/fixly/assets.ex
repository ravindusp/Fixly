defmodule Fixly.Assets do
  @moduledoc "Context for managing assets and ticket-asset links."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Assets.{Asset, TicketAssetLink}

  # --- Assets ---

  def get_asset!(id) do
    Asset
    |> Repo.get!(id)
    |> Repo.preload([:location, :organization, :ticket_asset_links])
  end

  def get_asset(id), do: Repo.get(Asset, id)

  @doc "List all assets for an organization."
  def list_assets(org_id) do
    Asset
    |> where([a], a.organization_id == ^org_id)
    |> order_by([a], [asc: a.name])
    |> preload([:location])
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

  @doc "Link a ticket to an asset by IDs with a linked_by source."
  def link_ticket_to_asset(ticket_id, asset_id, linked_by) do
    link_ticket_to_asset(%{
      ticket_id: ticket_id,
      asset_id: asset_id,
      linked_by: linked_by
    })
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
end
