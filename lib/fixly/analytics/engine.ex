defmodule Fixly.Analytics.Engine do
  @moduledoc """
  Composable analytics query engine for ticket data.
  All functions take and return Ecto queryables, so they can be piped together.
  """

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Tickets.Ticket

  @doc "Base query for tickets in an organization."
  def base_query(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
  end

  @doc "Filter tickets by a list of location IDs (includes descendants via ltree)."
  def for_locations(query, []), do: query
  def for_locations(query, location_ids) when is_list(location_ids) do
    # Get all descendant location IDs using ltree paths
    descendant_ids = get_descendant_ids(location_ids)
    all_ids = Enum.uniq(location_ids ++ descendant_ids)

    where(query, [t], t.location_id in ^all_ids)
  end

  @doc "Filter by date range."
  def in_date_range(query, nil, nil), do: query
  def in_date_range(query, from, nil) do
    where(query, [t], t.inserted_at >= ^from)
  end
  def in_date_range(query, nil, to) do
    where(query, [t], t.inserted_at <= ^to)
  end
  def in_date_range(query, from, to) do
    where(query, [t], t.inserted_at >= ^from and t.inserted_at <= ^to)
  end

  @doc "Filter by status."
  def with_status(query, nil), do: query
  def with_status(query, "all"), do: query
  def with_status(query, status) when is_binary(status) do
    where(query, [t], t.status == ^status)
  end
  def with_status(query, statuses) when is_list(statuses) do
    where(query, [t], t.status in ^statuses)
  end

  @doc "Filter by priority."
  def with_priority(query, nil), do: query
  def with_priority(query, "all"), do: query
  def with_priority(query, priority) when is_binary(priority) do
    where(query, [t], t.priority == ^priority)
  end

  @doc "Filter by category."
  def with_category(query, nil), do: query
  def with_category(query, "all"), do: query
  def with_category(query, category) when is_binary(category) do
    where(query, [t], t.category == ^category)
  end

  @doc "Filter by assigned contractor org."
  def with_contractor(query, nil), do: query
  def with_contractor(query, org_id) do
    where(query, [t], t.assigned_to_org_id == ^org_id)
  end

  # --- Aggregation ---

  @doc "Get aggregate stats for a query."
  def aggregate_stats(query) do
    total = Repo.aggregate(query, :count)

    status_counts =
      query
      |> group_by([t], t.status)
      |> select([t], {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    priority_counts =
      query
      |> where([t], not is_nil(t.priority))
      |> group_by([t], t.priority)
      |> select([t], {t.priority, count(t.id)})
      |> Repo.all()
      |> Map.new()

    category_counts =
      query
      |> where([t], not is_nil(t.category))
      |> group_by([t], t.category)
      |> select([t], {t.category, count(t.id)})
      |> Repo.all()
      |> Map.new()

    # SLA compliance
    sla_tickets = query |> where([t], not is_nil(t.sla_deadline)) |> Repo.aggregate(:count)
    sla_breached = query |> where([t], t.sla_breached == true) |> Repo.aggregate(:count)
    sla_compliance = if sla_tickets > 0, do: Float.round((sla_tickets - sla_breached) / sla_tickets * 100, 1), else: 100.0

    # Average resolution time (for completed tickets)
    avg_resolution =
      query
      |> where([t], t.status in ["completed", "reviewed", "closed"])
      |> where([t], not is_nil(t.sla_started_at))
      |> select([t], fragment("AVG(EXTRACT(EPOCH FROM (? - ?)))", t.updated_at, t.sla_started_at))
      |> Repo.one()

    avg_resolution_hours =
      if avg_resolution, do: avg_resolution |> Decimal.to_float() |> Kernel./(3600) |> Float.round(1), else: nil

    %{
      total: total,
      by_status: status_counts,
      by_priority: priority_counts,
      by_category: category_counts,
      sla_compliance: sla_compliance,
      sla_total: sla_tickets,
      sla_breached: sla_breached,
      avg_resolution_hours: avg_resolution_hours
    }
  end

  @doc "Get ticket counts grouped by time period."
  def group_by_period(query, period \\ :day) do
    trunc_fn = case period do
      :day -> "day"
      :week -> "week"
      :month -> "month"
    end

    {sql, params} = Repo.to_sql(:all, query |> select([t], t.inserted_at))

    raw_sql = """
    SELECT date_trunc($#{length(params) + 1}, sub.inserted_at) AS date, count(*) AS count
    FROM (#{sql}) AS sub
    GROUP BY date
    ORDER BY date
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, raw_sql, params ++ [trunc_fn])

    Enum.map(rows, fn [date, count] ->
      %{date: date, count: count}
    end)
  end

  @doc "Get breakdown by location for selected location IDs."
  def breakdown_by_location(query) do
    query
    |> where([t], not is_nil(t.location_id))
    |> join(:inner, [t], l in assoc(t, :location))
    |> group_by([t, l], [l.id, l.name])
    |> select([t, l], %{
      location_id: l.id,
      location_name: l.name,
      ticket_count: count(t.id),
      open: count(fragment("CASE WHEN ? IN ('created','triaged','assigned') THEN 1 END", t.status)),
      closed: count(fragment("CASE WHEN ? IN ('completed','reviewed','closed') THEN 1 END", t.status))
    })
    |> order_by([t, l], desc: count(t.id))
    |> Repo.all()
  end

  @doc "Get contractor performance stats."
  def contractor_performance(query) do
    query
    |> where([t], not is_nil(t.assigned_to_org_id))
    |> join(:inner, [t], o in assoc(t, :assigned_to_org))
    |> group_by([t, o], [o.id, o.name])
    |> select([t, o], %{
      org_id: o.id,
      org_name: o.name,
      total: count(t.id),
      completed: count(fragment("CASE WHEN ? IN ('completed','reviewed','closed') THEN 1 END", t.status)),
      breached: count(fragment("CASE WHEN ? = true THEN 1 END", t.sla_breached))
    })
    |> Repo.all()
  end

  # --- Helpers ---

  defp get_descendant_ids(location_ids) do
    # Use ltree to find all descendants
    locations = Repo.all(
      from l in Fixly.Locations.Location,
      where: l.id in ^location_ids,
      select: l.path
    )

    paths = Enum.filter(locations, & &1)

    if paths == [] do
      []
    else
      conditions = Enum.map(paths, fn path ->
        prefix = path <> "."
        dynamic([l], like(l.path, ^(prefix <> "%")))
      end)

      combined = Enum.reduce(conditions, fn cond, acc ->
        dynamic([l], ^acc or ^cond)
      end)

      from(l in Fixly.Locations.Location, where: ^combined, select: l.id)
      |> Repo.all()
    end
  end
end
