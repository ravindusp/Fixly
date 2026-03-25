defmodule Fixly.Tickets.TicketComment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(comment status_change assignment system)

  schema "ticket_comments" do
    field :body, :string
    field :internal, :boolean, default: false
    field :type, :string, default: "comment"
    field :metadata, :map, default: %{}

    belongs_to :ticket, Fixly.Tickets.Ticket
    belongs_to :user, Fixly.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:ticket_id, :user_id, :body, :internal, :type, :metadata])
    |> validate_required([:ticket_id, :body])
    |> validate_inclusion(:type, @types)
  end
end
