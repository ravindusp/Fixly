defmodule Fixly.Assets.Asset do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(operational needs_repair out_of_service retired)
  @created_via_options ~w(manual ai qr_scan import)

  schema "assets" do
    field :name, :string
    field :category, :string
    field :status, :string, default: "operational"
    field :created_via, :string, default: "manual"
    field :ai_confidence, :float
    field :qr_code_id, :string
    field :metadata, :map, default: %{}
    field :ticket_count, :integer, default: 0
    field :total_repair_cost, :decimal, default: 0

    belongs_to :location, Fixly.Locations.Location
    belongs_to :organization, Fixly.Organizations.Organization

    has_many :ticket_asset_links, Fixly.Assets.TicketAssetLink

    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :name,
      :category,
      :location_id,
      :organization_id,
      :status,
      :created_via,
      :ai_confidence,
      :qr_code_id,
      :metadata,
      :ticket_count,
      :total_repair_cost
    ])
    |> validate_required([:name, :organization_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:created_via, @created_via_options)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:qr_code_id)
  end

  def statuses, do: @statuses
end
