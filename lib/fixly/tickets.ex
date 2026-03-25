defmodule Fixly.Tickets do
  @moduledoc "Context for managing tickets, comments, and attachments."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Tickets.{Ticket, TicketAttachment, TicketComment, SLAEscalation}

  # --- Tickets ---

  def get_ticket!(id) do
    Ticket
    |> Repo.get!(id)
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
    |> preload([:location, :assigned_to_user, :assigned_to_org])
    |> Repo.all()
  end

  @doc "List tickets assigned to a specific contractor org."
  def list_contractor_tickets(contractor_org_id, opts \\ []) do
    Ticket
    |> where([t], t.assigned_to_org_id == ^contractor_org_id)
    |> apply_filters(opts)
    |> order_by([t], [desc: t.inserted_at])
    |> preload([:location, :assigned_to_user])
    |> Repo.all()
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

  @doc "Admin updates a ticket (status, priority, assignment)."
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.admin_changeset(attrs)
    |> Repo.update()
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

  @doc "List all active tickets that need an SLA check (have a deadline, not fully escalated)."
  def list_tickets_needing_sla_check do
    Ticket
    |> where([t], not is_nil(t.sla_deadline))
    |> where([t], not is_nil(t.sla_started_at))
    |> where([t], t.status in @active_sla_statuses)
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

  @doc "Mark a ticket as SLA breached."
  def mark_sla_breached(%Ticket{} = ticket) do
    ticket
    |> Ticket.sla_changeset(%{sla_breached: true})
    |> Repo.update()
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

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)

  defp maybe_filter_priority(query, nil), do: query
  defp maybe_filter_priority(query, priority), do: where(query, [t], t.priority == ^priority)

  defp maybe_filter_location(query, nil), do: query
  defp maybe_filter_location(query, location_id), do: where(query, [t], t.location_id == ^location_id)

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, category), do: where(query, [t], t.category == ^category)
end
