defmodule Fixly.Tickets.SLAEscalation do
  @moduledoc "Tracks SLA escalation thresholds that have been triggered for a ticket."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sla_escalations" do
    field :threshold, :integer
    field :notified_at, :utc_datetime
    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :notified_user, Fixly.Accounts.User, foreign_key: :notified_user_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @valid_thresholds [50, 75, 100, 150]

  def changeset(escalation, attrs) do
    escalation
    |> cast(attrs, [:ticket_id, :threshold, :notified_at, :notified_user_id])
    |> validate_required([:ticket_id, :threshold])
    |> validate_inclusion(:threshold, @valid_thresholds)
    |> unique_constraint([:ticket_id, :threshold])
    |> foreign_key_constraint(:ticket_id)
  end
end
