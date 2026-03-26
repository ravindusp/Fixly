defmodule Fixly.Repo.Migrations.AddOrgProfileFields do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :slug, :string
      add :display_code, :string
      add :phone, :string
      add :email, :string
      add :address, :text
      add :about, :text
      add :logo_url, :string
      add :timezone, :string, default: "Asia/Colombo"
    end

    create unique_index(:organizations, [:slug])
    create unique_index(:organizations, [:display_code])

    # Generate display codes for existing organizations
    execute(
      """
      UPDATE organizations
      SET display_code = 'FX-' || upper(substr(md5(random()::text), 1, 4))
      WHERE display_code IS NULL
      """,
      ""
    )

    # Generate slugs from names for existing organizations
    execute(
      """
      UPDATE organizations
      SET slug = lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(id::text, 1, 4)
      WHERE slug IS NULL
      """,
      ""
    )
  end
end
