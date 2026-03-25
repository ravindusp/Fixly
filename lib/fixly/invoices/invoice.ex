defmodule Fixly.Invoices.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending approved disputed)

  schema "invoices" do
    field :file_url, :string
    field :file_name, :string
    field :total_amount, :decimal
    field :currency, :string, default: "USD"
    field :line_items, {:array, :map}, default: []
    field :status, :string, default: "pending"
    field :approved_at, :utc_datetime
    field :notes, :string

    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :organization, Fixly.Organizations.Organization
    belongs_to :uploaded_by_user, Fixly.Accounts.User, foreign_key: :uploaded_by_user_id
    belongs_to :approved_by_user, Fixly.Accounts.User, foreign_key: :approved_by

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :ticket_id,
      :organization_id,
      :uploaded_by_user_id,
      :file_url,
      :file_name,
      :total_amount,
      :currency,
      :line_items,
      :status,
      :approved_by,
      :approved_at,
      :notes
    ])
    |> validate_required([:ticket_id, :organization_id, :total_amount])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:total_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:uploaded_by_user_id)
    |> foreign_key_constraint(:approved_by)
  end

  def statuses, do: @statuses
end
