defmodule Fixly.Repo.Migrations.AddOrgStatusAndSuperAdmin do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :status, :string, default: "active", null: false
    end

    # Set ravindusp@gmail.com as super_admin
    execute """
    UPDATE users SET role = 'super_admin'
    WHERE email = 'ravindusp@gmail.com'
    """
  end

  def down do
    alter table(:organizations) do
      remove :status
    end

    execute """
    UPDATE users SET role = 'org_admin'
    WHERE email = 'ravindusp@gmail.com'
    """
  end
end
