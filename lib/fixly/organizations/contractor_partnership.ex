defmodule Fixly.Organizations.ContractorPartnership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contractor_partnerships" do
    field :status, :string, default: "active"

    belongs_to :owner_org, Fixly.Organizations.Organization
    belongs_to :contractor_org, Fixly.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(partnership, attrs) do
    partnership
    |> cast(attrs, [:owner_org_id, :contractor_org_id, :status])
    |> validate_required([:owner_org_id, :contractor_org_id])
    |> validate_inclusion(:status, ["active", "inactive", "pending"])
    |> unique_constraint([:owner_org_id, :contractor_org_id])
  end
end
