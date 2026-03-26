defmodule Fixly.Repo.Migrations.CreateContractorPartnerships do
  use Ecto.Migration

  def change do
    create table(:contractor_partnerships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :owner_org_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :contractor_org_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contractor_partnerships, [:owner_org_id, :contractor_org_id])
    create index(:contractor_partnerships, [:contractor_org_id])

    # Data migration: copy existing parent_org_id relationships into the new table
    execute(
      """
      INSERT INTO contractor_partnerships (id, owner_org_id, contractor_org_id, status, inserted_at, updated_at)
      SELECT gen_random_uuid(), parent_org_id, id, 'active', NOW(), NOW()
      FROM organizations
      WHERE parent_org_id IS NOT NULL AND type = 'contractor'
      """,
      ""
    )
  end
end
