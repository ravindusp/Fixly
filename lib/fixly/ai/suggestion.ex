defmodule Fixly.AI.Suggestion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @suggestion_types ~w(link_asset create_asset category priority)
  @statuses ~w(pending approved rejected auto_applied)

  schema "ai_suggestions" do
    field :suggestion_type, :string
    field :suggested_data, :map
    field :confidence, :float
    field :reasoning, :string
    field :status, :string, default: "pending"
    field :reviewed_at, :utc_datetime

    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :reviewer, Fixly.Accounts.User, foreign_key: :reviewed_by

    timestamps(type: :utc_datetime)
  end

  def changeset(suggestion, attrs) do
    suggestion
    |> cast(attrs, [
      :ticket_id,
      :suggestion_type,
      :suggested_data,
      :confidence,
      :reasoning,
      :status,
      :reviewed_by,
      :reviewed_at
    ])
    |> validate_required([:ticket_id, :suggestion_type, :suggested_data])
    |> validate_inclusion(:suggestion_type, @suggestion_types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:reviewed_by)
  end

  def suggestion_types, do: @suggestion_types
  def statuses, do: @statuses
end
