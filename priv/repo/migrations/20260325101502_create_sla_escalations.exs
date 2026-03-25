defmodule Fixly.Repo.Migrations.CreateSlaEscalations do
  use Ecto.Migration

  def change do
    create table(:sla_escalations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :threshold, :integer, null: false
      add :notified_at, :utc_datetime
      add :notified_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:sla_escalations, [:ticket_id])
    create unique_index(:sla_escalations, [:ticket_id, :threshold])
  end
end
