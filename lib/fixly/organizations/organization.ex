defmodule Fixly.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(owner contractor)

  schema "organizations" do
    field :name, :string
    field :type, :string
    field :settings, :map, default: %{}
    field :slug, :string
    field :display_code, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :about, :string
    field :logo_url, :string
    field :timezone, :string, default: "Asia/Colombo"

    belongs_to :parent_org, __MODULE__, foreign_key: :parent_org_id
    has_many :child_orgs, __MODULE__, foreign_key: :parent_org_id
    has_many :locations, Fixly.Locations.Location
    has_many :users, Fixly.Accounts.User
    has_many :tickets, Fixly.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :type, :parent_org_id, :settings])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @types)
  end

  def profile_changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :phone, :email, :address, :about, :logo_url, :timezone, :slug])
    |> validate_required([:name])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> validate_length(:about, max: 2000)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/, message: "only lowercase letters, numbers, and hyphens")
    |> unique_constraint(:slug)
  end

  def types, do: @types
end
