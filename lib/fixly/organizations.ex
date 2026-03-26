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

  @doc "List incoming partnership invites for a contractor org."
  def list_incoming_invites(contractor_org_id) do
    from(cp in ContractorPartnership,
      where: cp.contractor_org_id == ^contractor_org_id and cp.status == "pending",
      join: o in assoc(cp, :owner_org),
      preload: [owner_org: o],
      order_by: [desc: cp.inserted_at]
    )
    |> Repo.all()
  end

  @doc "List active partnerships for a contractor org (owner orgs they work with)."
  def list_contractor_partnerships(contractor_org_id) do
    from(cp in ContractorPartnership,
      where: cp.contractor_org_id == ^contractor_org_id,
      join: o in assoc(cp, :owner_org),
      preload: [owner_org: o],
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

  @doc "Search contractor orgs by name or display code."
  def search_contractor_orgs(query_string) do
    pattern = "%#{query_string}%"

    from(o in Organization,
      where: o.type == "contractor",
      where: ilike(o.name, ^pattern) or o.display_code == ^String.upcase(query_string),
      limit: 10,
      order_by: o.name
    )
    |> Repo.all()
  end

  @doc "Find a contractor org by display code."
  def get_contractor_by_code(code) do
    Repo.get_by(Organization, display_code: String.upcase(code), type: "contractor")
  end

  @doc "Send a partnership invite (creates partnership with pending status)."
  def send_partnership_invite(owner_org_id, contractor_org_id) do
    # Check if partnership already exists
    existing =
      from(cp in ContractorPartnership,
        where:
          cp.owner_org_id == ^owner_org_id and
            cp.contractor_org_id == ^contractor_org_id and
            cp.status in ["active", "pending"]
      )
      |> Repo.one()

    case existing do
      nil ->
        %ContractorPartnership{}
        |> ContractorPartnership.changeset(%{
          owner_org_id: owner_org_id,
          contractor_org_id: contractor_org_id,
          status: "pending"
        })
        |> Repo.insert()

      %{status: "active"} ->
        {:error, :already_active}

      %{status: "pending"} ->
        {:error, :already_pending}
    end
  end

  @doc "Accept a pending partnership invite. Verifies the partnership involves the given org."
  def accept_partnership(partnership_id, org_id) do
    case Repo.get(ContractorPartnership, partnership_id) do
      %{status: "pending", owner_org_id: ^org_id} = partnership ->
        partnership
        |> ContractorPartnership.changeset(%{status: "active"})
        |> Repo.update()

      %{status: "pending", contractor_org_id: ^org_id} = partnership ->
        partnership
        |> ContractorPartnership.changeset(%{status: "active"})
        |> Repo.update()

      %{status: "pending"} ->
        {:error, :unauthorized}

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :not_pending}
    end
  end

  @doc "Decline a pending partnership invite. Verifies the partnership involves the given org."
  def decline_partnership(partnership_id, org_id) do
    case Repo.get(ContractorPartnership, partnership_id) do
      %{status: "pending", owner_org_id: ^org_id} = partnership ->
        Repo.delete(partnership)

      %{status: "pending", contractor_org_id: ^org_id} = partnership ->
        Repo.delete(partnership)

      %{status: "pending"} ->
        {:error, :unauthorized}

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :not_pending}
    end
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

  # --- Organization status management (super admin) ---

  @doc "List organizations by status."
  def list_organizations_by_status(status) do
    from(o in Organization,
      where: o.status == ^status,
      order_by: [desc: o.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Count organizations by status."
  def count_organizations_by_status do
    from(o in Organization,
      group_by: o.status,
      select: {o.status, count(o.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Approve a pending organization."
  def approve_organization(org_id) do
    case Repo.get(Organization, org_id) do
      nil -> {:error, :not_found}
      org ->
        org
        |> Organization.status_changeset(%{status: "active"})
        |> Repo.update()
    end
  end

  @doc "Reject a pending organization (deletes org and its users)."
  def reject_organization(org_id) do
    case Repo.get(Organization, org_id) do
      nil -> {:error, :not_found}
      org -> Repo.delete(org)
    end
  end

  @doc "Suspend an active organization."
  def suspend_organization(org_id) do
    case Repo.get(Organization, org_id) do
      nil -> {:error, :not_found}
      org ->
        org
        |> Organization.status_changeset(%{status: "suspended"})
        |> Repo.update()
    end
  end

  @doc "Reactivate a suspended organization."
  def reactivate_organization(org_id) do
    case Repo.get(Organization, org_id) do
      nil -> {:error, :not_found}
      org ->
        org
        |> Organization.status_changeset(%{status: "active"})
        |> Repo.update()
    end
  end

  @doc "Get organization with owner user preloaded."
  def get_organization_with_owner(org_id) do
    org = Repo.get(Organization, org_id)

    if org do
      owner =
        from(u in Fixly.Accounts.User,
          where: u.organization_id == ^org_id,
          where: u.role in ["org_admin", "contractor_admin"],
          order_by: [asc: u.inserted_at],
          limit: 1
        )
        |> Repo.one()

      {org, owner}
    end
  end

  @doc "Count team members in an organization."
  def count_team_members(org_id) do
    from(u in Fixly.Accounts.User,
      where: u.organization_id == ^org_id,
      where: not is_nil(u.confirmed_at)
    )
    |> Repo.aggregate(:count, :id)
  end

  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Ecto.Changeset.put_change(:display_code, generate_display_code())
    |> Ecto.Changeset.put_change(:slug, generate_slug(attrs[:name] || attrs["name"] || "org"))
    |> Repo.insert()
  end

  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def update_profile(%Organization{} = org, attrs) do
    org
    |> Organization.profile_changeset(attrs)
    |> Repo.update()
  end

  def delete_organization(%Organization{} = org) do
    Repo.delete(org)
  end

  # Generate a unique display code like "FX-7K4X"
  defp generate_display_code do
    code = "FX-" <> random_code(4)

    if Repo.get_by(Organization, display_code: code) do
      generate_display_code()
    else
      code
    end
  end

  defp random_code(length) do
    chars = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end

  defp generate_slug(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    suffix = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
    slug = "#{base}-#{suffix}"

    if Repo.get_by(Organization, slug: slug) do
      generate_slug(name)
    else
      slug
    end
  end
end
