defmodule Fixly.AI do
  @moduledoc "Context for managing AI suggestions."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.AI.Suggestion

  def get_suggestion!(id), do: Repo.get!(Suggestion, id)

  @doc "List pending AI suggestions for an org, newest first."
  def list_pending_suggestions(org_id) do
    Suggestion
    |> join(:inner, [s], t in assoc(s, :ticket))
    |> where([s, t], t.organization_id == ^org_id)
    |> where([s], s.status == "pending")
    |> order_by([s], [desc: s.inserted_at])
    |> preload([s, t], ticket: t)
    |> Repo.all()
  end

  @doc "Count pending suggestions for an org."
  def count_pending_suggestions(org_id) do
    Suggestion
    |> join(:inner, [s], t in assoc(s, :ticket))
    |> where([s, t], t.organization_id == ^org_id)
    |> where([s], s.status == "pending")
    |> Repo.aggregate(:count)
  end

  @doc "Create a suggestion."
  def create_suggestion(attrs) do
    %Suggestion{}
    |> Suggestion.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Approve a suggestion."
  def approve_suggestion(suggestion, reviewed_by_user_id) do
    suggestion
    |> Suggestion.changeset(%{
      status: "approved",
      reviewed_by: reviewed_by_user_id,
      reviewed_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  @doc "Reject a suggestion."
  def reject_suggestion(suggestion, reviewed_by_user_id) do
    suggestion
    |> Suggestion.changeset(%{
      status: "rejected",
      reviewed_by: reviewed_by_user_id,
      reviewed_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  @doc "Bulk approve all suggestions above a confidence threshold."
  def bulk_approve_high_confidence(org_id, threshold \\ 0.9, user_id) do
    now = DateTime.utc_now(:second)

    Suggestion
    |> join(:inner, [s], t in assoc(s, :ticket))
    |> where([s, t], t.organization_id == ^org_id)
    |> where([s], s.status == "pending" and s.confidence >= ^threshold)
    |> Repo.update_all(set: [status: "approved", reviewed_by: user_id, reviewed_at: now])
  end
end
