defmodule Fixly.Organizations do
  @moduledoc "Context for managing organizations (owner orgs and contractor companies)."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Organizations.{Organization, ContractorPartnership}

  def get_organization!(id), do: Repo.get!(Organization, id)

  def get_organization(id), do: Repo.get(Organization, id)

  def list_organizations do
    Repo.all(Organization)
  end

  @doc "List contractor orgs via partnerships (replaces parent_org_id query)."
  def list_contractor_orgs(owner_org_id) do
    from(o in Organization,
      join: cp in ContractorPartnership,
      on: cp.contractor_org_id == o.id,
      where: cp.owner_org_id == ^owner_org_id and cp.status == "active",
      select: o
    )
    |> Repo.all()
  end

  @doc "List all partnerships for an owner org."
  def list_partnerships(owner_org_id) do
    from(cp in ContractorPartnership,
      where: cp.owner_org_id == ^owner_org_id,
      join: o in assoc(cp, :contractor_org),
      preload: [contractor_org: o],
      order_by: [desc: cp.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Check if a partnership exists between an owner org and a contractor org."
  def partnership_exists?(owner_org_id, contractor_org_id) do
    from(cp in ContractorPartnership,
      where:
        cp.owner_org_id == ^owner_org_id and
          cp.contractor_org_id == ^contractor_org_id and
          cp.status == "active"
    )
    |> Repo.exists?()
  end

  @doc "Create a new contractor org and partnership in one transaction."
  def create_contractor_org_with_partnership(contractor_attrs, owner_org_id) do
    Repo.transact(fn ->
      org_attrs = Map.merge(contractor_attrs, %{type: "contractor", parent_org_id: owner_org_id})

      with {:ok, org} <- create_organization(org_attrs) do
        partnership_attrs = %{
          owner_org_id: owner_org_id,
          contractor_org_id: org.id,
          status: "active"
        }

        case %ContractorPartnership{}
             |> ContractorPartnership.changeset(partnership_attrs)
             |> Repo.insert() do
          {:ok, _partnership} -> {:ok, org}
          {:error, changeset} -> {:error, changeset}
        end
      end
    end)
  end

  @doc "Deactivate a partnership."
  def deactivate_partnership(partnership_id) do
    case Repo.get(ContractorPartnership, partnership_id) do
      nil ->
        {:error, :not_found}

      partnership ->
        partnership
        |> ContractorPartnership.changeset(%{status: "inactive"})
        |> Repo.update()
    end
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
