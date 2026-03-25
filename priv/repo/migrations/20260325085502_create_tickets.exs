defmodule Fixly.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    # Tickets
    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reference_number, :string, null: false
      add :location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
      add :organization_id,
        references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :description, :text, null: false
      add :category, :string
      add :custom_location_name, :string
      add :custom_item_name, :string

      add :status, :string, null: false, default: "created"
      add :priority, :string

      # Submitter
      add :submitter_name, :string
      add :submitter_email, :string
      add :submitter_phone, :string
      add :submitter_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :verified, :boolean, default: false

      # Assignment
      add :assigned_to_org_id,
        references(:organizations, type: :binary_id, on_delete: :nilify_all)
      add :assigned_to_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # SLA
      add :sla_deadline, :utc_datetime
      add :sla_started_at, :utc_datetime
      add :sla_paused_at, :utc_datetime
      add :sla_total_paused_seconds, :integer, default: 0
      add :sla_breached, :boolean, default: false

      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tickets, [:reference_number])
    create index(:tickets, [:organization_id])
    create index(:tickets, [:location_id])
    create index(:tickets, [:status])
    create index(:tickets, [:priority])
    create index(:tickets, [:assigned_to_org_id])
    create index(:tickets, [:assigned_to_user_id])
    create index(:tickets, [:sla_deadline], where: "sla_deadline IS NOT NULL")
    create index(:tickets, [:inserted_at])

    # Ticket attachments
    create table(:ticket_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :file_url, :string, null: false
      add :file_type, :string
      add :file_name, :string
      add :file_size, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:ticket_attachments, [:ticket_id])

    # Ticket comments / activity log
    create table(:ticket_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :body, :text, null: false
      add :internal, :boolean, default: false
      add :type, :string, default: "comment"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:ticket_comments, [:ticket_id])
    create index(:ticket_comments, [:user_id])

    # Sequence for human-readable ticket reference numbers per org
    execute(
      "CREATE SEQUENCE ticket_reference_seq START 1",
      "DROP SEQUENCE IF EXISTS ticket_reference_seq"
    )
  end
end
