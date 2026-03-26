defmodule Fixly.Tickets.StatusMachine do
  @moduledoc """
  Role-based status transition rules for tickets.

  Defines which status transitions each role is allowed to make,
  and whether proof-of-completion is required.
  """

  @admin_transitions %{
    "created" => ["triaged"],
    "triaged" => ["assigned"],
    "assigned" => ["in_progress"],
    "in_progress" => ["on_hold", "completed"],
    "on_hold" => ["in_progress"],
    "completed" => ["reviewed", "in_progress"],
    "reviewed" => ["closed"],
    "closed" => []
  }

  @contractor_transitions %{
    "assigned" => ["in_progress"],
    "in_progress" => ["on_hold", "completed"],
    "on_hold" => ["in_progress"]
  }

  # Technicians have same transitions as contractors
  @technician_transitions @contractor_transitions

  @doc """
  Returns the list of valid next statuses for a given role and current status.
  """
  def allowed_transitions(role, current_status) do
    transitions_for_role(role)
    |> Map.get(current_status, [])
  end

  @doc """
  Checks whether a role can transition from current to target status.
  """
  def can_transition?(role, current_status, target_status) do
    target_status in allowed_transitions(role, current_status)
  end

  @doc """
  Returns true if transitioning to the target status requires proof (attachments).
  Only "completed" requires proof.
  """
  def requires_proof?(target_status) do
    target_status == "completed"
  end

  defp transitions_for_role(role) when role in ["super_admin", "org_admin"], do: @admin_transitions
  defp transitions_for_role("contractor_admin"), do: @contractor_transitions
  defp transitions_for_role("technician"), do: @technician_transitions
  defp transitions_for_role("resident"), do: %{}
  defp transitions_for_role(_), do: %{}
end
