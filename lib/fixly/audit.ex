defmodule Fixly.Audit do
  @moduledoc "Context for audit logging."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Audit.AuditLog

  @doc """
  Log an auditable action.

  ## Parameters
    - organization_id: the org context
    - user_id: who performed the action (nil for system actions)
    - action: e.g. "create", "update", "delete", "assign", "status_change"
    - resource_type: e.g. "ticket", "asset", "invoice", "user"
    - resource_id: the UUID of the resource
    - opts: optional keyword list with :changes and :ip_address
  """
  def log_action(organization_id, user_id, action, resource_type, resource_id, opts \\ []) do
    attrs = %{
      organization_id: organization_id,
      user_id: user_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      changes: Keyword.get(opts, :changes, %{}),
      ip_address: Keyword.get(opts, :ip_address)
    }

    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  List audit logs for an organization with optional filters.

  ## Options
    - :user_id - filter by user
    - :resource_type - filter by resource type
    - :action - filter by action
    - :resource_id - filter by specific resource
    - :limit - max number of results (default 50)
    - :offset - pagination offset (default 0)
  """
  def list_audit_logs(org_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    AuditLog
    |> where([al], al.organization_id == ^org_id)
    |> maybe_filter_user(opts[:user_id])
    |> maybe_filter_resource_type(opts[:resource_type])
    |> maybe_filter_action(opts[:action])
    |> maybe_filter_resource_id(opts[:resource_id])
    |> order_by([al], [desc: al.inserted_at])
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:user])
    |> Repo.all()
  end

  @doc "Count audit logs for an organization with optional filters."
  def count_audit_logs(org_id, opts \\ []) do
    AuditLog
    |> where([al], al.organization_id == ^org_id)
    |> maybe_filter_user(opts[:user_id])
    |> maybe_filter_resource_type(opts[:resource_type])
    |> maybe_filter_action(opts[:action])
    |> maybe_filter_resource_id(opts[:resource_id])
    |> Repo.aggregate(:count)
  end

  # --- Filter Helpers ---

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [al], al.user_id == ^user_id)

  defp maybe_filter_resource_type(query, nil), do: query

  defp maybe_filter_resource_type(query, resource_type),
    do: where(query, [al], al.resource_type == ^resource_type)

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: where(query, [al], al.action == ^action)

  defp maybe_filter_resource_id(query, nil), do: query

  defp maybe_filter_resource_id(query, resource_id),
    do: where(query, [al], al.resource_id == ^resource_id)
end
