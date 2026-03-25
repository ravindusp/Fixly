defmodule Fixly.PubSubBroadcast do
  @moduledoc "Broadcasts ticket events via Phoenix PubSub for real-time dashboard updates."

  @pubsub Fixly.PubSub

  # --- Topics ---

  def org_topic(org_id), do: "tickets:org:#{org_id}"
  def user_topic(user_id), do: "tickets:user:#{user_id}"
  def contractor_topic(org_id), do: "tickets:contractor:#{org_id}"
  def ticket_topic(ticket_id), do: "ticket:#{ticket_id}"

  # --- Subscribe ---

  def subscribe_org(org_id) do
    Phoenix.PubSub.subscribe(@pubsub, org_topic(org_id))
  end

  def subscribe_user(user_id) do
    Phoenix.PubSub.subscribe(@pubsub, user_topic(user_id))
  end

  def subscribe_contractor(org_id) do
    Phoenix.PubSub.subscribe(@pubsub, contractor_topic(org_id))
  end

  def subscribe_ticket(ticket_id) do
    Phoenix.PubSub.subscribe(@pubsub, ticket_topic(ticket_id))
  end

  # --- Broadcast ---

  @doc "Broadcast that a new ticket was created."
  def broadcast_ticket_created(ticket) do
    broadcast(org_topic(ticket.organization_id), {:ticket_created, ticket})
  end

  @doc "Broadcast that a ticket was updated (status, priority, assignment, etc)."
  def broadcast_ticket_updated(ticket) do
    broadcast(org_topic(ticket.organization_id), {:ticket_updated, ticket})

    if ticket.assigned_to_org_id do
      broadcast(contractor_topic(ticket.assigned_to_org_id), {:ticket_updated, ticket})
    end

    if ticket.assigned_to_user_id do
      broadcast(user_topic(ticket.assigned_to_user_id), {:ticket_updated, ticket})
    end

    broadcast(ticket_topic(ticket.id), {:ticket_updated, ticket})
  end

  @doc "Broadcast that a new comment was added to a ticket."
  def broadcast_comment_added(ticket, comment) do
    broadcast(ticket_topic(ticket.id), {:comment_added, comment})
    broadcast(org_topic(ticket.organization_id), {:ticket_updated, ticket})
  end

  @doc "Broadcast SLA breach."
  def broadcast_sla_breach(ticket) do
    broadcast(org_topic(ticket.organization_id), {:sla_breached, ticket})

    if ticket.assigned_to_user_id do
      broadcast(user_topic(ticket.assigned_to_user_id), {:sla_breached, ticket})
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast_from(@pubsub, self(), topic, message)
  end
end
