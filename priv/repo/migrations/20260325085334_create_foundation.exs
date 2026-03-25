defmodule Fixly.Repo.Migrations.CreateFoundation do
  use Ecto.Migration

  def up do
    # Enable ltree extension for hierarchical path queries
    execute "CREATE EXTENSION IF NOT EXISTS ltree"

    # Organizations: the school (owner) and contractor companies
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :parent_org_id, references(:organizations, type: :binary_id, on_delete: :nilify_all)
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:organizations, [:parent_org_id])
    create index(:organizations, [:type])

    # Location tree: fully recursive, arbitrary depth
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :label, :string, null: false
      add :parent_id, references(:locations, type: :binary_id, on_delete: :delete_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false
      add :depth, :integer, null: false, default: 0
      add :path, :string
      add :qr_code_id, :string
      add :position, :integer, default: 0
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:locations, [:parent_id])
    create index(:locations, [:organization_id])
    create unique_index(:locations, [:qr_code_id], where: "qr_code_id IS NOT NULL")
    create index(:locations, [:depth])
    execute "CREATE INDEX locations_path_gist_idx ON locations USING gist (CAST(path AS ltree))"
  end

  def down do
    execute "DROP INDEX IF EXISTS locations_path_gist_idx"
    drop table(:locations)
    drop table(:organizations)
    execute "DROP EXTENSION IF EXISTS ltree"
  end
end
