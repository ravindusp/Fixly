defmodule Fixly.Notifications do
  @moduledoc "Handles sending email notifications for ticket events."

  alias Fixly.Mailer
  alias Fixly.Notifications.TicketEmail

  @doc "Notify org admins that a new ticket was submitted."
  def notify_new_ticket(ticket) do
    ticket
    |> TicketEmail.new_ticket_email()
    |> Mailer.deliver()
  end

  @doc "Notify contractor admin that a ticket was assigned to their company."
  def notify_ticket_assigned_to_contractor(ticket, contractor_org) do
    ticket
    |> TicketEmail.assigned_to_contractor_email(contractor_org)
    |> Mailer.deliver()
  end

  @doc "Notify technician that a ticket was assigned to them."
  def notify_ticket_assigned_to_technician(ticket, technician) do
    ticket
    |> TicketEmail.assigned_to_technician_email(technician)
    |> Mailer.deliver()
  end

  @doc "Notify submitter that their ticket status changed."
  def notify_status_change(ticket) do
    if ticket.submitter_email do
      ticket
      |> TicketEmail.status_change_email()
      |> Mailer.deliver()
    end
  end

  @doc "Notify submitter that their ticket was resolved."
  def notify_ticket_resolved(ticket) do
    if ticket.submitter_email do
      ticket
      |> TicketEmail.resolved_email()
      |> Mailer.deliver()
    end
  end
end
