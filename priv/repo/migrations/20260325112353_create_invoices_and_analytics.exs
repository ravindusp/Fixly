defmodule Fixly.Repo.Migrations.CreateInvoicesAndAnalytics do
  use Ecto.Migration

  def change do
    # Invoices table
    create table(:invoices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :organization_id,
        references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :uploaded_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :file_url, :string
      add :file_name, :string
      add :total_amount, :decimal, null: false
      add :currency, :string, default: "USD"
      add :line_items, {:array, :map}, default: []
      add :status, :string, default: "pending"
      add :approved_by, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :approved_at, :utc_datetime
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:invoices, [:ticket_id])
    create index(:invoices, [:organization_id])
    create index(:invoices, [:status])

    # Time entries table
    create table(:time_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :hours, :decimal, null: false
      add :hourly_rate, :decimal
      add :description, :text
      add :date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:time_entries, [:ticket_id])
    create index(:time_entries, [:user_id])

    # Saved views table
    create table(:saved_views, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :organization_id,
        references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :selected_location_ids, {:array, :string}, default: []
      add :filters, :map, default: %{}
      add :metrics, :map, default: %{}
      add :grouping, :string
      add :sort, :map, default: %{}
      add :chart_preferences, :map, default: %{}
      add :pinned, :boolean, default: false
      add :shared, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:saved_views, [:user_id])
    create index(:saved_views, [:organization_id])
  end
end
