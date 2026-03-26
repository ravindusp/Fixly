defmodule Fixly.Workers.NotificationWorker do
  @moduledoc "Oban worker for sending ticket notifications asynchronously."

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Fixly.Tickets
  alias Fixly.Organizations
  alias Fixly.Accounts
  alias Fixly.Notifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "new_ticket", "ticket_id" => ticket_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    Notifications.notify_new_ticket(ticket)
  end

  def perform(%Oban.Job{args: %{"type" => "assigned_to_contractor", "ticket_id" => ticket_id, "org_id" => org_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    org = Organizations.get_organization!(org_id)
    Notifications.notify_ticket_assigned_to_contractor(ticket, org)
  end

  def perform(%Oban.Job{args: %{"type" => "assigned_to_technician", "ticket_id" => ticket_id, "user_id" => user_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = Accounts.get_user!(user_id)
    Notifications.notify_ticket_assigned_to_technician(ticket, user)
  end

  def perform(%Oban.Job{args: %{"type" => "status_change", "ticket_id" => ticket_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    Notifications.notify_status_change(ticket)
  end

  def perform(%Oban.Job{args: %{"type" => "resolved", "ticket_id" => ticket_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    Notifications.notify_ticket_resolved(ticket)
  end

  def perform(%Oban.Job{args: %{"type" => "sla_warning", "ticket_id" => ticket_id, "user_id" => user_id, "threshold" => threshold}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    user = Accounts.get_user!(user_id)
    Notifications.notify_sla_warning(ticket, user, threshold)
  end

  def perform(%Oban.Job{args: %{"type" => "sla_breach", "ticket_id" => ticket_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    Notifications.notify_sla_breach(ticket)
  end

  def perform(%Oban.Job{args: %{"type" => "sla_critical", "ticket_id" => ticket_id, "org_id" => org_id}}) do
    ticket = Tickets.get_ticket!(ticket_id)
    org = Organizations.get_organization!(org_id)
    Notifications.notify_sla_critical(ticket, org)
  end

  # --- Convenience functions to enqueue jobs ---

  def enqueue_new_ticket(ticket_id) do
    %{"type" => "new_ticket", "ticket_id" => ticket_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_assigned_to_contractor(ticket_id, org_id) do
    %{"type" => "assigned_to_contractor", "ticket_id" => ticket_id, "org_id" => org_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_assigned_to_technician(ticket_id, user_id) do
    %{"type" => "assigned_to_technician", "ticket_id" => ticket_id, "user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_status_change(ticket_id) do
    %{"type" => "status_change", "ticket_id" => ticket_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_resolved(ticket_id) do
    %{"type" => "resolved", "ticket_id" => ticket_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_sla_warning(ticket_id, user_id, threshold) do
    %{"type" => "sla_warning", "ticket_id" => ticket_id, "user_id" => user_id, "threshold" => threshold}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_sla_breach(ticket_id) do
    %{"type" => "sla_breach", "ticket_id" => ticket_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def enqueue_sla_critical(ticket_id, org_id) do
    %{"type" => "sla_critical", "ticket_id" => ticket_id, "org_id" => org_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
