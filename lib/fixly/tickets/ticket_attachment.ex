defmodule Fixly.Tickets.TicketAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ticket_attachments" do
    field :file_url, :string
    field :file_type, :string
    field :file_name, :string
    field :file_size, :integer

    belongs_to :ticket, Fixly.Tickets.Ticket

    timestamps(type: :utc_datetime)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:ticket_id, :file_url, :file_type, :file_name, :file_size])
    |> validate_required([:ticket_id, :file_url])
  end
end
