defmodule Fixly.Audit.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :changes, :map, default: %{}
    field :ip_address, :string

    belongs_to :organization, Fixly.Organizations.Organization
    belongs_to :user, Fixly.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :organization_id,
      :user_id,
      :action,
      :resource_type,
      :resource_id,
      :changes,
      :ip_address
    ])
    |> validate_required([:organization_id, :action, :resource_type])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
  end
end
