defmodule Fixly.Notifications.TicketEmail do
  @moduledoc "Email templates for ticket notifications."

  import Swoosh.Email

  @from {"Fixly", "notifications@fixly.app"}

  def new_ticket_email(ticket) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    new()
    |> to(admin_email())
    |> from(@from)
    |> subject("New Ticket: #{ticket.reference_number} — #{location_name}")
    |> text_body("""
    A new maintenance ticket has been submitted.

    Reference: #{ticket.reference_number}
    Location: #{location_name}
    Category: #{ticket.category || "Not specified"}
    Description: #{ticket.description}

    Submitted by: #{ticket.submitter_name || "Anonymous"}
    Email: #{ticket.submitter_email || "Not provided"}
    Phone: #{ticket.submitter_phone || "Not provided"}

    View ticket: #{url()}/admin/tickets/#{ticket.id}
    """)
  end

  def assigned_to_contractor_email(ticket, contractor_org) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    # In a real app, we'd look up the contractor admin's email
    new()
    |> to(admin_email())
    |> from(@from)
    |> subject("Ticket Assigned: #{ticket.reference_number} — #{contractor_org.name}")
    |> text_body("""
    A ticket has been assigned to #{contractor_org.name}.

    Reference: #{ticket.reference_number}
    Location: #{location_name}
    Priority: #{ticket.priority || "Not set"}
    Description: #{ticket.description}

    View ticket: #{url()}/contractor/tickets/#{ticket.id}
    """)
  end

  def assigned_to_technician_email(ticket, technician) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    new()
    |> to(technician.email)
    |> from(@from)
    |> subject("Ticket Assigned to You: #{ticket.reference_number}")
    |> text_body("""
    A maintenance ticket has been assigned to you.

    Reference: #{ticket.reference_number}
    Location: #{location_name}
    Priority: #{ticket.priority || "Not set"}
    Category: #{ticket.category || "Not specified"}
    Description: #{ticket.description}

    Submitter: #{ticket.submitter_name || "Anonymous"}
    Phone: #{ticket.submitter_phone || "Not provided"}

    View ticket: #{url()}/tech/tickets
    """)
  end

  def status_change_email(ticket) do
    status_text = status_label(ticket.status)

    new()
    |> to(ticket.submitter_email)
    |> from(@from)
    |> subject("Ticket #{ticket.reference_number} — #{status_text}")
    |> text_body("""
    Your maintenance ticket has been updated.

    Reference: #{ticket.reference_number}
    New Status: #{status_text}

    Thank you for your patience.
    """)
  end

  def resolved_email(ticket) do
    new()
    |> to(ticket.submitter_email)
    |> from(@from)
    |> subject("Ticket #{ticket.reference_number} — Resolved")
    |> text_body("""
    Your maintenance ticket has been resolved.

    Reference: #{ticket.reference_number}
    Description: #{ticket.description}

    If the issue persists, please submit a new ticket by scanning the QR code again.

    Thank you!
    """)
  end

  def sla_warning_email(ticket, technician, threshold) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    new()
    |> to(technician.email)
    |> from(@from)
    |> subject("SLA Warning: #{ticket.reference_number} — #{threshold}% elapsed")
    |> text_body("""
    SLA WARNING: #{threshold}% of the SLA time has elapsed.

    Reference: #{ticket.reference_number}
    Location: #{location_name}
    Priority: #{ticket.priority || "Not set"}
    SLA Deadline: #{ticket.sla_deadline}

    Please take action to resolve this ticket before the deadline.

    View ticket: #{url()}/tech/tickets
    """)
  end

  def sla_breach_email(ticket) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    new()
    |> to(admin_email())
    |> from(@from)
    |> subject("SLA BREACHED: #{ticket.reference_number}")
    |> text_body("""
    SLA BREACHED: The deadline for this ticket has passed.

    Reference: #{ticket.reference_number}
    Location: #{location_name}
    Priority: #{ticket.priority || "Not set"}
    SLA Deadline: #{ticket.sla_deadline}
    Status: #{ticket.status}

    Immediate attention is required.

    View ticket: #{url()}/admin/tickets/#{ticket.id}
    """)
  end

  def sla_critical_email(ticket, org) do
    location_name = if ticket.location, do: ticket.location.name, else: "Unknown location"

    new()
    |> to(admin_email())
    |> from(@from)
    |> subject("SLA CRITICAL: #{ticket.reference_number} — 150% overdue (#{org.name})")
    |> text_body("""
    CRITICAL: This ticket is 150% past its SLA deadline.

    Reference: #{ticket.reference_number}
    Organization: #{org.name}
    Location: #{location_name}
    Priority: #{ticket.priority || "Not set"}
    SLA Deadline: #{ticket.sla_deadline}
    Status: #{ticket.status}

    This ticket requires immediate executive attention.

    View ticket: #{url()}/admin/tickets/#{ticket.id}
    """)
  end

  defp status_label("created"), do: "Open"
  defp status_label("triaged"), do: "Triaged"
  defp status_label("assigned"), do: "Assigned"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("on_hold"), do: "On Hold"
  defp status_label("completed"), do: "Completed"
  defp status_label("reviewed"), do: "Reviewed"
  defp status_label("closed"), do: "Closed"
  defp status_label(other), do: String.capitalize(to_string(other))

  # Placeholder — in production, look up org admin emails dynamically
  defp admin_email, do: "admin@fixly.app"

  defp url do
    FixlyWeb.Endpoint.url()
  end
end
