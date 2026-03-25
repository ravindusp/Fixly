defmodule Fixly.Repo.Migrations.CreateAssetsAndAi do
  use Ecto.Migration

  def change do
    # Assets table
    create table(:assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :category, :string
      add :location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
      add :organization_id,
        references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :status, :string, default: "operational"
      add :created_via, :string, default: "manual"
      add :ai_confidence, :float
      add :qr_code_id, :string
      add :metadata, :map, default: %{}
      add :ticket_count, :integer, default: 0
      add :total_repair_cost, :decimal, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:assets, [:organization_id])
    create index(:assets, [:location_id])
    create index(:assets, [:category])
    create index(:assets, [:status])
    create unique_index(:assets, [:qr_code_id], where: "qr_code_id IS NOT NULL")

    # Ticket-Asset link table (many-to-many)
    create table(:ticket_asset_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :asset_id, references(:assets, type: :binary_id, on_delete: :delete_all), null: false
      add :linked_by, :string

      timestamps(type: :utc_datetime)
    end

    create index(:ticket_asset_links, [:ticket_id])
    create index(:ticket_asset_links, [:asset_id])
    create unique_index(:ticket_asset_links, [:ticket_id, :asset_id])

    # AI Suggestions table
    create table(:ai_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :suggestion_type, :string, null: false
      add :suggested_data, :map, null: false
      add :confidence, :float
      add :reasoning, :text
      add :status, :string, default: "pending"
      add :reviewed_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:ai_suggestions, [:ticket_id])
    create index(:ai_suggestions, [:status])
    create index(:ai_suggestions, [:suggestion_type])
  end
end
