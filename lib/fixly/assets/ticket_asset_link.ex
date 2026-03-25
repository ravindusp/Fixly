defmodule Fixly.Assets.TicketAssetLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ticket_asset_links" do
    field :linked_by, :string

    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :asset, Fixly.Assets.Asset

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:ticket_id, :asset_id, :linked_by])
    |> validate_required([:ticket_id, :asset_id])
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:asset_id)
    |> unique_constraint([:ticket_id, :asset_id])
  end
end
