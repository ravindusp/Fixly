defmodule Fixly.Analytics do
  @moduledoc "Context for ticket analytics and saved views."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Tickets.Ticket
  alias Fixly.Analytics.SavedView

  # --- Ticket Analytics ---

  @doc "Count tickets grouped by status for an organization."
  def tickets_by_status(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count tickets grouped by priority for an organization."
  def tickets_by_priority(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> group_by([t], t.priority)
    |> select([t], {t.priority, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count tickets grouped by category for an organization."
  def tickets_by_category(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> group_by([t], t.category)
    |> select([t], {t.category, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count tickets grouped by location for an organization."
  def tickets_by_location(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id and not is_nil(t.location_id))
    |> join(:left, [t], l in assoc(t, :location))
    |> group_by([t, l], [t.location_id, l.name])
    |> select([t, l], {l.name, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count tickets created per day over a date range."
  def tickets_per_day(org_id, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> where([t], t.inserted_at >= ^start_dt and t.inserted_at <= ^end_dt)
    |> group_by([t], fragment("DATE(?)", t.inserted_at))
    |> select([t], {fragment("DATE(?)", t.inserted_at), count(t.id)})
    |> order_by([t], fragment("DATE(?)", t.inserted_at))
    |> Repo.all()
  end

  @doc "Count SLA breaches for an organization."
  def sla_breach_count(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id and t.sla_breached == true)
    |> Repo.aggregate(:count)
  end

  @doc "Composable base query for ticket analytics with optional filters."
  def ticket_query(org_id, opts \\ []) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> maybe_filter_locations(opts[:location_ids])
    |> maybe_filter_statuses(opts[:statuses])
    |> maybe_filter_priorities(opts[:priorities])
    |> maybe_filter_categories(opts[:categories])
    |> maybe_filter_date_range(opts[:start_date], opts[:end_date])
  end

  # --- Saved Views ---

  def get_saved_view!(id), do: Repo.get!(SavedView, id)

  def get_saved_view(id), do: Repo.get(SavedView, id)

  @doc "List saved views for a user within an organization."
  def list_saved_views(user_id, org_id) do
    SavedView
    |> where([sv], sv.user_id == ^user_id and sv.organization_id == ^org_id)
    |> order_by([sv], [desc: sv.pinned, asc: sv.name])
    |> Repo.all()
  end

  @doc "List shared saved views for an organization."
  def list_shared_views(org_id) do
    SavedView
    |> where([sv], sv.organization_id == ^org_id and sv.shared == true)
    |> order_by([sv], [asc: sv.name])
    |> Repo.all()
  end

  def create_saved_view(attrs) do
    %SavedView{}
    |> SavedView.changeset(attrs)
    |> Repo.insert()
  end

  def update_saved_view(%SavedView{} = saved_view, attrs) do
    saved_view
    |> SavedView.changeset(attrs)
    |> Repo.update()
  end

  def delete_saved_view(%SavedView{} = saved_view) do
    Repo.delete(saved_view)
  end

  # --- Filter Helpers ---

  defp maybe_filter_locations(query, nil), do: query
  defp maybe_filter_locations(query, []), do: query

  defp maybe_filter_locations(query, location_ids) do
    where(query, [t], t.location_id in ^location_ids)
  end

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query
  defp maybe_filter_statuses(query, statuses), do: where(query, [t], t.status in ^statuses)

  defp maybe_filter_priorities(query, nil), do: query
  defp maybe_filter_priorities(query, []), do: query
  defp maybe_filter_priorities(query, priorities), do: where(query, [t], t.priority in ^priorities)

  defp maybe_filter_categories(query, nil), do: query
  defp maybe_filter_categories(query, []), do: query
  defp maybe_filter_categories(query, categories), do: where(query, [t], t.category in ^categories)

  defp maybe_filter_date_range(query, nil, _), do: query
  defp maybe_filter_date_range(query, _, nil), do: query

  defp maybe_filter_date_range(query, start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query
    |> where([t], t.inserted_at >= ^start_dt and t.inserted_at <= ^end_dt)
  end
end
