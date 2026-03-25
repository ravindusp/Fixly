defmodule Fixly.Workers.AITicketWorker do
  @moduledoc "Oban worker that triggers AI processing for new tickets."

  use Oban.Worker, queue: :ai, max_attempts: 3

  alias Fixly.AI.TicketProcessor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id}}) do
    case TicketProcessor.process(ticket_id) do
      :ok -> :ok
      {:error, :no_api_key} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Enqueue AI processing for a ticket."
  def enqueue(ticket_id) do
    %{"ticket_id" => ticket_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
