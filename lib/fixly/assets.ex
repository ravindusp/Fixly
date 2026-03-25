defmodule Fixly.Assets do
  @moduledoc "Context for managing assets and ticket-asset links."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Assets.{Asset, TicketAssetLink}
  alias Fixly.Tickets.Ticket

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
