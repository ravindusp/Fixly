defmodule Fixly.Locations.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "locations" do
    field :name, :string
    field :label, :string
    field :depth, :integer, default: 0
    field :path, :string
    field :qr_code_id, :string
    field :position, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    belongs_to :organization, Fixly.Organizations.Organization

    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :tickets, Fixly.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :label, :parent_id, :organization_id, :position, :metadata])
    |> validate_required([:name, :label, :organization_id])
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:organization_id)
  end
end
