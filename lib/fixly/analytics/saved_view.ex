defmodule Fixly.Analytics.SavedView do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_views" do
    field :name, :string
    field :selected_location_ids, {:array, :string}, default: []
    field :filters, :map, default: %{}
    field :metrics, :map, default: %{}
    field :grouping, :string
    field :sort, :map, default: %{}
    field :chart_preferences, :map, default: %{}
    field :pinned, :boolean, default: false
    field :shared, :boolean, default: false

    belongs_to :user, Fixly.Accounts.User
    belongs_to :organization, Fixly.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(saved_view, attrs) do
    saved_view
    |> cast(attrs, [
      :name,
      :user_id,
      :organization_id,
      :selected_location_ids,
      :filters,
      :metrics,
      :grouping,
      :sort,
      :chart_preferences,
      :pinned,
      :shared
    ])
    |> validate_required([:name, :user_id, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
