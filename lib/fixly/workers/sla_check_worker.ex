defmodule Fixly.Workers.SLACheckWorker do
  @moduledoc """
  Oban cron worker that runs every 60 seconds to check SLA deadlines.

  For each active ticket with an SLA deadline, calculates the percentage of
  SLA time elapsed and triggers escalations at defined thresholds:

    - 50%  : Dashboard visual indicator (no notification)
    - 75%  : Notify the assigned technician
    - 100% : Mark as breached, notify supervisor / contractor admin
    - 150% : Notify school admin (org admin)
  """

  use Oban.Worker, queue: :sla, max_attempts: 1

  alias Fixly.Tickets
  alias Fixly.Workers.NotificationWorker

  require Logger

  @thresholds [50, 75, 100, 150]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    tickets = Tickets.list_tickets_needing_sla_check()
    now = DateTime.utc_now(:second)

    # Compute SLA percentage for each ticket up front
    tickets_with_pct =
      tickets
      |> Enum.map(fn ticket ->
        elapsed = calculate_elapsed_seconds(ticket, now)
        total = calculate_total_sla_seconds(ticket)
        pct = if total > 0, do: elapsed / total * 100, else: 0.0
        {ticket, pct}
      end)
      |> Enum.filter(fn {_ticket, pct} -> pct > 0.0 end)

    ticket_ids = Enum.map(tickets_with_pct, fn {t, _} -> t.id end)

    # Batch-fetch existing escalations per threshold
    existing_by_threshold =
      Map.new(@thresholds, fn threshold ->
        {threshold, Tickets.existing_escalations(ticket_ids, threshold)}
      end)

    # Process each ticket, skipping already-escalated thresholds
    Enum.each(tickets_with_pct, fn {ticket, pct} ->
      Enum.each(@thresholds, fn threshold ->
        already_exists = MapSet.member?(existing_by_threshold[threshold], ticket.id)

        if pct >= threshold and not already_exists do
          handle_threshold(ticket, threshold, now)
        end
      end)
    end)

    :ok
  end

  defp calculate_elapsed_seconds(ticket, now) do
    raw_elapsed = DateTime.diff(now, ticket.sla_started_at, :second)
    paused = ticket.sla_total_paused_seconds || 0

    # If currently paused, don't count time since pause started
    currently_paused =
      if ticket.sla_paused_at do
        DateTime.diff(now, ticket.sla_paused_at, :second)
      else
        0
      end

    max(raw_elapsed - paused - currently_paused, 0)
  end

  defp calculate_total_sla_seconds(ticket) do
    # The original SLA duration (before any pauses extended the deadline)
    # total_sla_seconds = deadline - started_at - total_paused_seconds
    # But since deadline was extended by paused seconds via resume_sla,
    # the original duration is: deadline - started_at - total_paused_seconds
    paused = ticket.sla_total_paused_seconds || 0

    # If currently paused, the deadline hasn't been extended yet for this pause,
    # so the original duration is just deadline - started_at - already_accounted_paused
    DateTime.diff(ticket.sla_deadline, ticket.sla_started_at, :second) - paused
  end

  defp handle_threshold(ticket, 50, now) do
    # 50% — dashboard visual indicator only, no notification
    Logger.info("SLA 50% reached for ticket #{ticket.id}")

    Tickets.create_escalation(%{
      ticket_id: ticket.id,
      threshold: 50,
      notified_at: now
    })

    Tickets.log_activity(ticket.id, "sla_warning", "SLA 50% elapsed — monitor closely.")
  end

  defp handle_threshold(ticket, 75, now) do
    # 75% — notify assigned technician
    Logger.warning("SLA 75% reached for ticket #{ticket.id}")

    notified_user_id = ticket.assigned_to_user_id

    Tickets.create_escalation(%{
      ticket_id: ticket.id,
      threshold: 75,
      notified_at: now,
      notified_user_id: notified_user_id
    })

    Tickets.log_activity(ticket.id, "sla_warning", "SLA 75% elapsed — technician notified.")

    if notified_user_id do
      NotificationWorker.enqueue_sla_warning(ticket.id, notified_user_id, 75)
    end
  end

  defp handle_threshold(ticket, 100, now) do
    # 100% — SLA breached, notify supervisor / contractor admin
    Logger.error("SLA BREACHED for ticket #{ticket.id}")

    Tickets.mark_sla_breached(ticket)

    Tickets.create_escalation(%{
      ticket_id: ticket.id,
      threshold: 100,
      notified_at: now
    })

    Tickets.log_activity(ticket.id, "sla_breach", "SLA breached — supervisor notified.")
    NotificationWorker.enqueue_sla_breach(ticket.id)
  end

  defp handle_threshold(ticket, 150, now) do
    # 150% — critical, notify school admin (org admin)
    Logger.error("SLA 150% overdue for ticket #{ticket.id}")

    Tickets.create_escalation(%{
      ticket_id: ticket.id,
      threshold: 150,
      notified_at: now
    })

    Tickets.log_activity(ticket.id, "sla_critical", "SLA 150% overdue — org admin notified.")
    NotificationWorker.enqueue_sla_critical(ticket.id, ticket.organization_id)
  end
end
