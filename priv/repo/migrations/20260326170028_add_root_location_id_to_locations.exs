defmodule Fixly.Repo.Migrations.AddRootLocationIdToLocations do
  use Ecto.Migration

  def up do
    alter table(:locations) do
      add :root_location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
    end

    flush()

    # Backfill: root locations point to themselves
    execute """
    UPDATE locations SET root_location_id = id WHERE parent_id IS NULL
    """

    # For non-root locations, extract the root path segment and find the matching root
    execute """
    UPDATE locations AS child
    SET root_location_id = root.id
    FROM locations AS root
    WHERE child.parent_id IS NOT NULL
      AND root.parent_id IS NULL
      AND root.organization_id = child.organization_id
      AND root.path = split_part(child.path, '.', 1)
    """

    create index(:locations, [:root_location_id])
  end

  def down do
    drop index(:locations, [:root_location_id])

    alter table(:locations) do
      remove :root_location_id
    end
  end
end
