defmodule Fixly.Invoices.TimeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "time_entries" do
    field :hours, :decimal
    field :hourly_rate, :decimal
    field :description, :string
    field :date, :date

    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :user, Fixly.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(time_entry, attrs) do
    time_entry
    |> cast(attrs, [:ticket_id, :user_id, :hours, :hourly_rate, :description, :date])
    |> validate_required([:ticket_id, :user_id, :hours, :date])
    |> validate_number(:hours, greater_than: 0)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:user_id)
  end
end
