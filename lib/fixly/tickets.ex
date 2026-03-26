defmodule Fixly.Tickets do
  @moduledoc "Context for managing tickets, comments, and attachments."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Tickets.{Ticket, TicketAttachment, TicketComment, SLAEscalation, StatusMachine}

  # --- Tickets ---

  @doc "Recent tickets for dashboard widget."
  def list_recent_tickets(org_id, limit \\ 5) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> order_by([t], desc: t.inserted_at)
    |> limit(^limit)
    |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
    |> Repo.all()
  end

  @doc "Overdue tickets for dashboard widget."
  def list_overdue_tickets(org_id) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> where([t], t.sla_breached == true)
    |> where([t], t.status not in ["completed", "reviewed", "closed"])
    |> order_by([t], asc: t.sla_deadline)
    |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
    |> Repo.all()
  end

  @doc "Count tickets grouped by status for stat cards."
  def count_tickets_by_status(org_id, filters \\ %{}) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> apply_db_filters(filters)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Paginated ticket list with DB-level filtering."
  def list_tickets_paginated(org_id, filters \\ %{}, cursor \\ nil) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> apply_db_filters(filters)
    |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
    |> Fixly.Pagination.paginate_desc(cursor: cursor)
  end

  @doc """
  List tickets grouped by status with a per-status limit.
  Returns `[{status, %{tickets: [...], total: n, has_more: bool}}, ...]`.
  """
  def list_tickets_by_status(org_id, filters \\ %{}, per_status_limit \\ 20) do
    statuses = ~w(created triaged assigned in_progress on_hold pending_review completed reviewed closed)

    # Get total counts per status in one query
    total_counts = count_tickets_by_status(org_id, filters)

    Enum.map(statuses, fn status ->
      tickets =
        Ticket
        |> where([t], t.organization_id == ^org_id and t.status == ^status)
        |> apply_db_filters(filters)
        |> order_by([t], desc: t.inserted_at)
        |> limit(^per_status_limit)
        |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
        |> Repo.all()

      total = Map.get(total_counts, status, 0)

      {status, %{tickets: tickets, total: total, has_more: total > per_status_limit}}
    end)
  end

  @doc "Load more tickets for a specific status (offset-based for kanban/grouped list)."
  def list_tickets_for_status(org_id, status, filters \\ %{}, offset \\ 0, limit \\ 20) do
    Ticket
    |> where([t], t.organization_id == ^org_id and t.status == ^status)
    |> apply_db_filters(filters)
    |> order_by([t], desc: t.inserted_at)
    |> offset(^offset)
    |> limit(^limit)
    |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
    |> Repo.all()
  end

  def get_ticket!(id) do
    Ticket
    |> Repo.get!(id)
    |> Repo.preload([:location, :attachments, :comments, :assigned_to_user, :assigned_to_org])
  end

  @doc "Fetch a ticket scoped to an organization. Raises if not found or wrong org."
  def get_ticket_for_org!(org_id, id) do
    Ticket
    |> where(organization_id: ^org_id, id: ^id)
    |> Repo.one!()
    |> Repo.preload([:location, :attachments, :comments, :assigned_to_user, :assigned_to_org])
  end

  @doc "Fetch a ticket scoped to a contractor org (by assigned_to_org_id). Raises if not found."
  def get_ticket_for_contractor_org!(contractor_org_id, id) do
    Ticket
    |> where(assigned_to_org_id: ^contractor_org_id, id: ^id)
    |> Repo.one!()
    |> Repo.preload([:location, :attachments, :comments, :assigned_to_user, :assigned_to_org])
  end

  def get_ticket(id), do: Repo.get(Ticket, id)

  def get_ticket_by_reference(reference_number) do
    Repo.get_by(Ticket, reference_number: reference_number)
  end

  @doc "List tickets for an organization with optional filters."
  def list_tickets(org_id, opts \\ []) do
    Ticket
    |> where([t], t.organization_id == ^org_id)
    |> apply_filters(opts)
    |> order_by([t], [desc: t.inserted_at])
    |> preload([[location: :root_location], :assigned_to_user, :assigned_to_org])
    |> Repo.all()
  end

  @doc "List tickets assigned to a specific contractor org."
  def list_contractor_tickets(contractor_org_id, opts \\ []) do
    Ticket
    |> where([t], t.assigned_to_org_id == ^contractor_org_id)
    |> apply_filters(opts)
    |> order_by([t], [desc: t.inserted_at])
    |> preload([[location: :root_location], :assigned_to_user])
    |> Repo.all()
  end

  @doc "Paginated contractor tickets with DB counts."
  def list_contractor_tickets_paginated(contractor_org_id, cursor \\ nil) do
    Ticket
    |> where([t], t.assigned_to_org_id == ^contractor_org_id)
    |> preload([[location: :root_location], :assigned_to_user])
    |> Fixly.Pagination.paginate_desc(cursor: cursor)
  end

  @doc "List contractor tickets grouped by status for kanban."
  def list_contractor_tickets_by_status(contractor_org_id, per_status_limit \\ 20) do
    statuses = ~w(assigned in_progress on_hold pending_review completed)
    total_counts = count_contractor_tickets_by_status(contractor_org_id)

    Enum.map(statuses, fn status ->
      tickets =
        Ticket
        |> where([t], t.assigned_to_org_id == ^contractor_org_id and t.status == ^status)
        |> order_by([t], desc: t.inserted_at)
        |> limit(^per_status_limit)
        |> preload([[location: :root_location], :assigned_to_user])
        |> Repo.all()

      total = Map.get(total_counts, status, 0)
      {status, %{tickets: tickets, total: total, has_more: total > per_status_limit}}
    end)
  end

  @doc "Count contractor tickets by status."
  def count_contractor_tickets_by_status(contractor_org_id) do
    Ticket
    |> where([t], t.assigned_to_org_id == ^contractor_org_id)
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get contractor ticket stats scoped to a specific owner org's tickets."
  def contractor_stats_for_owner(contractor_org_id, owner_org_id) do
    base =
      Ticket
      |> where([t], t.assigned_to_org_id == ^contractor_org_id)
      |> where([t], t.organization_id == ^owner_org_id)

    total = Repo.aggregate(base, :count, :id)

    status_counts =
      base
      |> group_by([t], t.status)
      |> select([t], {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    completed_statuses = ~w(completed reviewed closed)
    active_statuses = ~w(assigned in_progress on_hold)

    completed = Enum.reduce(completed_statuses, 0, &(Map.get(status_counts, &1, 0) + &2))
    active = Enum.reduce(active_statuses, 0, &(Map.get(status_counts, &1, 0) + &2))

    breached =
      base
      |> where([t], t.sla_breached == true)
      |> Repo.aggregate(:count, :id)

    avg_resolution_hours =
      base
      |> where([t], t.status in ^completed_statuses)
      |> select([t], fragment("AVG(EXTRACT(EPOCH FROM (? - ?)) / 3600)", t.updated_at, t.inserted_at))
      |> Repo.one()

    priority_counts =
      base
      |> where([t], not is_nil(t.priority))
      |> group_by([t], t.priority)
      |> select([t], {t.priority, count(t.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: total,
      completed: completed,
      active: active,
      status_counts: status_counts,
      breached: breached,
      sla_compliance_rate: if(total > 0, do: Float.round((total - breached) / total * 100.0, 1), else: 100.0),
      avg_resolution_hours: if(avg_resolution_hours, do: avg_resolution_hours |> Decimal.to_float() |> Float.round(1), else: nil),
      priority_counts: priority_counts
    }
  end

  @doc "Paginated technician tickets."
  def list_user_tickets_paginated(user_id, cursor \\ nil) do
    Ticket
    |> where([t], t.assigned_to_user_id == ^user_id)
    |> where([t], t.status not in ["closed", "reviewed"])
    |> preload([:location, :attachments])
    |> Fixly.Pagination.paginate_desc(cursor: cursor)
  end

  @doc "Count active tickets for a technician."
  def count_user_tickets(user_id) do
    Ticket
    |> where([t], t.assigned_to_user_id == ^user_id)
    |> where([t], t.status not in ["closed", "reviewed"])
    |> Repo.aggregate(:count, :id)
  end

  @doc "Paginated completed tickets for a technician."
  def list_user_completed_tickets_paginated(user_id, cursor \\ nil) do
    Ticket
    |> where([t], t.assigned_to_user_id == ^user_id)
    |> where([t], t.status in ["completed", "reviewed", "closed"])
    |> preload([:location, :attachments])
    |> Fixly.Pagination.paginate_desc(cursor: cursor)
  end

  @doc "Count completed tickets for a technician."
  def count_user_completed_tickets(user_id) do
    Ticket
    |> where([t], t.assigned_to_user_id == ^user_id)
    |> where([t], t.status in ["completed", "reviewed", "closed"])
    |> Repo.aggregate(:count, :id)
  end

  @doc "Paginated resident tickets (by submitter)."
  def list_resident_tickets_paginated(user_id, user_email, cursor \\ nil) do
    Ticket
    |> where([t], t.submitter_user_id == ^user_id or t.submitter_email == ^(user_email || ""))
    |> preload([:location, :attachments])
    |> Fixly.Pagination.paginate_desc(cursor: cursor)
  end

  @doc "Count resident tickets."
  def count_resident_tickets(user_id, user_email) do
    Ticket
    |> where([t], t.submitter_user_id == ^user_id or t.submitter_email == ^(user_email || ""))
    |> Repo.aggregate(:count, :id)
  end

  @doc "List tickets assigned to a specific technician."
  def list_user_tickets(user_id) do
    Ticket
    |> where([t], t.assigned_to_user_id == ^user_id)
    |> where([t], t.status not in ["closed", "reviewed"])
    |> order_by([t], [asc: t.sla_deadline, desc: t.inserted_at])
    |> preload([:location, :attachments])
    |> Repo.all()
  end

  @doc "Create a ticket from a public QR submission."
  def create_ticket(attrs) do
    reference = generate_reference_number()

    %Ticket{}
    |> Ticket.submission_changeset(attrs)
    |> Ecto.Changeset.put_change(:reference_number, reference)
    |> Repo.insert()
  end

  @doc "Admin updates a ticket (status, priority, assignment). Checks linked assets when closing."
  def update_ticket(%Ticket{} = ticket, attrs) do
    old_status = ticket.status

    result =
      ticket
      |> Ticket.admin_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_ticket} ->
        new_status = updated_ticket.status

        # If ticket status changed to closed/completed, check all linked assets
        if new_status != old_status and new_status in ["closed", "completed", "reviewed"] do
          check_linked_assets_for_ticket(updated_ticket.id)
        end

        {:ok, updated_ticket}

      error ->
        error
    end
  end

  @doc "Set priority and start SLA timer."
  def set_priority(%Ticket{} = ticket, priority) do
    sla_hours = sla_hours_for_priority(priority)
    now = DateTime.utc_now(:second)

    sla_attrs =
      if sla_hours do
        deadline = DateTime.add(now, sla_hours * 3600, :second)

        %{
          sla_started_at: now,
          sla_deadline: deadline,
          sla_paused_at: nil,
          sla_total_paused_seconds: 0,
          sla_breached: false
        }
      else
        %{
          sla_started_at: now,
          sla_deadline: nil,
          sla_paused_at: nil,
          sla_total_paused_seconds: 0,
          sla_breached: false
        }
      end

    ticket
    |> Ticket.admin_changeset(Map.put(sla_attrs, :priority, priority))
    |> Repo.update()
  end

  @doc "Pause the SLA timer (e.g., ticket moved to on_hold)."
  def pause_sla(%Ticket{sla_paused_at: nil} = ticket) do
    ticket
    |> Ticket.sla_changeset(%{sla_paused_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  def pause_sla(ticket), do: {:ok, ticket}

  @doc "Resume the SLA timer (ticket back to in_progress)."
  def resume_sla(%Ticket{sla_paused_at: paused_at, sla_deadline: deadline} = ticket)
      when not is_nil(paused_at) and not is_nil(deadline) do
    now = DateTime.utc_now(:second)
    paused_seconds = DateTime.diff(now, paused_at, :second)
    total_paused = (ticket.sla_total_paused_seconds || 0) + paused_seconds
    new_deadline = DateTime.add(deadline, paused_seconds, :second)

    ticket
    |> Ticket.sla_changeset(%{
      sla_paused_at: nil,
      sla_total_paused_seconds: total_paused,
      sla_deadline: new_deadline
    })
    |> Repo.update()
  end

  def resume_sla(ticket), do: {:ok, ticket}

  @doc "Assign a ticket to an org and/or user."
  def assign_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.admin_changeset(
      Map.merge(attrs, %{status: "assigned"})
    )
    |> Repo.update()
  end

  # --- SLA Escalations ---

  @active_sla_statuses ~w(assigned in_progress on_hold)

  @sla_check_batch_size 500

  @doc """
  List active tickets that need an SLA check.
  Only returns tickets whose deadline is within 2x the check interval (120 minutes)
  from now, limited to a batch size of #{@sla_check_batch_size}.
  """
  def list_tickets_needing_sla_check do
    horizon = DateTime.utc_now(:second) |> DateTime.add(120 * 60, :second)

    Ticket
    |> where([t], not is_nil(t.sla_deadline))
    |> where([t], not is_nil(t.sla_started_at))
    |> where([t], t.status in @active_sla_statuses)
    |> where([t], t.sla_deadline <= ^horizon)
    |> order_by([t], asc: t.sla_deadline)
    |> limit(@sla_check_batch_size)
    |> Repo.all()
  end

  @doc "Create an SLA escalation record."
  def create_escalation(attrs) do
    %SLAEscalation{}
    |> SLAEscalation.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Check if an escalation record already exists for a ticket at a given threshold."
  def escalation_exists?(ticket_id, threshold) do
    SLAEscalation
    |> where([e], e.ticket_id == ^ticket_id and e.threshold == ^threshold)
    |> Repo.exists?()
  end

  @doc "Return the set of ticket IDs that already have an escalation at the given threshold."
  def existing_escalations(ticket_ids, threshold) do
    SLAEscalation
    |> where([e], e.ticket_id in ^ticket_ids and e.threshold == ^threshold)
    |> select([e], e.ticket_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Mark a ticket as SLA breached."
  def mark_sla_breached(%Ticket{} = ticket) do
    ticket
    |> Ticket.sla_changeset(%{sla_breached: true})
    |> Repo.update()
  end

  @doc """
  Update ticket status with role-based transition validation and proof-of-completion gate.

  Returns:
    - `{:ok, ticket}` on success
    - `{:error, :unauthorized_transition}` if the role can't make this transition
    - `{:error, :proof_required}` if completing without attachments
    - `{:error, changeset}` on other validation failure
  """
  def update_ticket_status(%Ticket{} = ticket, new_status, user) do
    role = user.role
    current_status = ticket.status

    cond do
      !StatusMachine.can_transition?(role, current_status, new_status) ->
        {:error, :unauthorized_transition}

      StatusMachine.requires_proof?(new_status) && count_attachments(ticket.id) == 0 ->
        {:error, :proof_required}

      true ->
        # Handle SLA pause/resume
        case new_status do
          "on_hold" -> pause_sla(ticket)
          "in_progress" when current_status == "on_hold" -> resume_sla(ticket)
          _ -> :ok
        end

        update_ticket(ticket, %{status: new_status})
    end
  end

  @doc "Count attachments for a ticket."
  def count_attachments(ticket_id) do
    TicketAttachment
    |> where([a], a.ticket_id == ^ticket_id)
    |> Repo.aggregate(:count, :id)
  end

  # --- Assignment with authorization ---

  @doc """
  Assign a ticket to a contractor org. Validates the user is an admin and the partnership exists.
  """
  def assign_to_contractor_org(%Ticket{} = ticket, org_id, admin_user) do
    cond do
      admin_user.role not in ["super_admin", "org_admin"] ->
        {:error, :unauthorized}

      !Fixly.Organizations.partnership_exists?(ticket.organization_id, org_id) ->
        {:error, :no_partnership}

      true ->
        assign_ticket(ticket, %{assigned_to_org_id: org_id})
    end
  end

  @doc """
  Assign a ticket to a technician. Validates the contractor admin owns the ticket
  and the technician belongs to their org.
  """
  def assign_to_technician(%Ticket{} = ticket, user_id, contractor_admin) do
    tech = Fixly.Accounts.get_user!(user_id)

    cond do
      contractor_admin.role != "contractor_admin" ->
        {:error, :unauthorized}

      ticket.assigned_to_org_id != contractor_admin.organization_id ->
        {:error, :not_your_ticket}

      tech.organization_id != contractor_admin.organization_id ->
        {:error, :tech_not_in_org}

      true ->
        assign_ticket(ticket, %{assigned_to_user_id: user_id})
    end
  end

  # --- Comments ---

  def list_comments(ticket_id) do
    TicketComment
    |> where([c], c.ticket_id == ^ticket_id)
    |> order_by([c], [asc: c.inserted_at])
    |> preload(:user)
    |> Repo.all()
  end

  def create_comment(attrs) do
    %TicketComment{}
    |> TicketComment.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Add a system comment to log status changes, assignments, etc."
  def log_activity(ticket_id, type, body, metadata \\ %{}) do
    create_comment(%{
      ticket_id: ticket_id,
      body: body,
      type: type,
      internal: true,
      metadata: metadata
    })
  end

  @doc """
  Log a structured ticket event with proper type and metadata.
  This is the main entry point for logging all ticket activity timeline events.
  """
  def log_ticket_event(ticket_id, type, body, metadata \\ %{})

  def log_ticket_event(ticket_id, "created", body, metadata) do
    log_activity(ticket_id, "created", body, metadata)
  end

  def log_ticket_event(ticket_id, "status_change", body, metadata) do
    log_activity(ticket_id, "status_change", body, metadata)
  end

  def log_ticket_event(ticket_id, "assignment", body, metadata) do
    log_activity(ticket_id, "assignment", body, metadata)
  end

  def log_ticket_event(ticket_id, "priority_change", body, metadata) do
    log_activity(ticket_id, "priority_change", body, metadata)
  end

  def log_ticket_event(ticket_id, "category_change", body, metadata) do
    log_activity(ticket_id, "category_change", body, metadata)
  end

  def log_ticket_event(ticket_id, "asset_linked", body, metadata) do
    log_activity(ticket_id, "asset_linked", body, metadata)
  end

  def log_ticket_event(ticket_id, "sla_breach", body, metadata) do
    log_activity(ticket_id, "sla_breach", body, metadata)
  end

  def log_ticket_event(ticket_id, type, body, metadata) do
    log_activity(ticket_id, type, body, metadata)
  end

  # --- Attachments ---

  def create_attachment(attrs) do
    %TicketAttachment{}
    |> TicketAttachment.changeset(attrs)
    |> Repo.insert()
  end

  # --- Helpers ---

  defp generate_reference_number do
    # Use database sequence for guaranteed uniqueness
    %{rows: [[num]]} = Repo.query!("SELECT nextval('ticket_reference_seq')")
    "TK-#{String.pad_leading(Integer.to_string(num), 4, "0")}"
  end

  defp sla_hours_for_priority("emergency"), do: 4
  defp sla_hours_for_priority("high"), do: 24
  defp sla_hours_for_priority("medium"), do: 48
  defp sla_hours_for_priority("low"), do: nil
  defp sla_hours_for_priority(_), do: nil

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_priority(opts[:priority])
    |> maybe_filter_location(opts[:location_id])
    |> maybe_filter_category(opts[:category])
  end

  @doc false
  def apply_db_filters(query, filters) when is_map(filters) do
    query
    |> maybe_filter_status(filters[:status] || filters["status"])
    |> maybe_filter_priority(filters[:priority] || filters["priority"])
    |> maybe_filter_location(filters[:location_id] || filters["location_id"])
    |> maybe_filter_category(filters[:category] || filters["category"])
    |> maybe_filter_date_from(filters[:date_from] || filters["date_from"])
    |> maybe_filter_date_to(filters[:date_to] || filters["date_to"])
    |> maybe_filter_assignees(filters[:assignee_ids] || filters["assignee_ids"])
    |> maybe_filter_search(filters[:search] || filters["search"])
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, "all"), do: query
  defp maybe_filter_status(query, %MapSet{} = s) do
    if MapSet.size(s) == 0, do: query, else: where(query, [t], t.status in ^MapSet.to_list(s))
  end
  defp maybe_filter_status(query, vals) when is_list(vals) do
    if vals == [], do: query, else: where(query, [t], t.status in ^vals)
  end
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)

  defp maybe_filter_priority(query, nil), do: query
  defp maybe_filter_priority(query, "all"), do: query
  defp maybe_filter_priority(query, %MapSet{} = p) do
    if MapSet.size(p) == 0, do: query, else: where(query, [t], t.priority in ^MapSet.to_list(p))
  end
  defp maybe_filter_priority(query, vals) when is_list(vals) do
    if vals == [], do: query, else: where(query, [t], t.priority in ^vals)
  end
  defp maybe_filter_priority(query, priority), do: where(query, [t], t.priority == ^priority)

  defp maybe_filter_location(query, nil), do: query
  defp maybe_filter_location(query, "all"), do: query
  defp maybe_filter_location(query, %MapSet{} = ids) do
    if MapSet.size(ids) == 0, do: query, else: filter_location_with_descendants(query, MapSet.to_list(ids))
  end
  defp maybe_filter_location(query, ids) when is_list(ids) do
    if ids == [], do: query, else: filter_location_with_descendants(query, ids)
  end
  defp maybe_filter_location(query, location_id), do: filter_location_with_descendants(query, [location_id])

  defp filter_location_with_descendants(query, location_ids) do
    # Get paths for selected locations, then match any ticket whose location
    # is either one of the selected locations or a descendant (via ltree <@)
    parent_paths =
      Fixly.Locations.Location
      |> where([l], l.id in ^location_ids)
      |> select([l], l.path)
      |> Fixly.Repo.all()

    query
    |> join(:inner, [t], l in Fixly.Locations.Location, on: t.location_id == l.id, as: :filter_loc)
    |> where(
      [t, filter_loc: l],
      l.id in ^location_ids or
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?::text[]) AS p WHERE CAST(? AS ltree) <@ CAST(p AS ltree))",
          ^parent_paths,
          l.path
        )
    )
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, "all"), do: query
  defp maybe_filter_category(query, %MapSet{} = c) do
    if MapSet.size(c) == 0, do: query, else: where(query, [t], t.category in ^MapSet.to_list(c))
  end
  defp maybe_filter_category(query, vals) when is_list(vals) do
    if vals == [], do: query, else: where(query, [t], t.category in ^vals)
  end
  defp maybe_filter_category(query, category), do: where(query, [t], t.category == ^category)

  defp maybe_filter_date_from(query, nil), do: query
  defp maybe_filter_date_from(query, date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        from = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        where(query, [t], t.inserted_at >= ^from)
      _ -> query
    end
  end
  defp maybe_filter_date_from(query, _), do: query

  defp maybe_filter_date_to(query, nil), do: query
  defp maybe_filter_date_to(query, date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        to = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        where(query, [t], t.inserted_at <= ^to)
      _ -> query
    end
  end
  defp maybe_filter_date_to(query, _), do: query

  defp maybe_filter_assignees(query, nil), do: query
  defp maybe_filter_assignees(query, ids) when is_list(ids) and ids != [] do
    where(query, [t], t.assigned_to_user_id in ^ids or t.assigned_to_org_id in ^ids)
  end
  defp maybe_filter_assignees(query, %MapSet{} = ids) do
    if MapSet.size(ids) == 0, do: query, else: maybe_filter_assignees(query, MapSet.to_list(ids))
  end
  defp maybe_filter_assignees(query, _), do: query

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query
  defp maybe_filter_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"

    query
    |> join(:left, [t], l in assoc(t, :location), as: :search_location)
    |> where(
      [t, search_location: l],
      ilike(t.description, ^pattern) or
        ilike(t.reference_number, ^pattern) or
        ilike(coalesce(t.submitter_name, ""), ^pattern) or
        ilike(coalesce(t.category, ""), ^pattern) or
        ilike(coalesce(l.name, ""), ^pattern)
    )
  end

  # Check all linked assets for a ticket and restore operational status if all tickets are resolved.
  defp check_linked_assets_for_ticket(ticket_id) do
    alias Fixly.Assets
    links = Assets.list_links_for_ticket(ticket_id)

    Enum.each(links, fn link ->
      Assets.check_and_restore_operational(link.asset_id)
    end)
  end
end
