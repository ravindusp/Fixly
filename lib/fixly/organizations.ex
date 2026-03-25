defmodule Fixly.Organizations do
  @moduledoc "Context for managing organizations (owner orgs and contractor companies)."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Organizations.Organization

  def get_organization!(id), do: Repo.get!(Organization, id)

  def get_organization(id), do: Repo.get(Organization, id)

  def list_organizations do
    Repo.all(Organization)
  end

  def list_contractor_orgs(owner_org_id) do
    Organization
    |> where([o], o.parent_org_id == ^owner_org_id and o.type == "contractor")
    |> Repo.all()
  end

  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def delete_organization(%Organization{} = org) do
    Repo.delete(org)
  end
end
