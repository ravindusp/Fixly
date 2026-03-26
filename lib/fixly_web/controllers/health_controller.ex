defmodule FixlyWeb.HealthController do
  @moduledoc "Minimal health and readiness endpoints."

  use FixlyWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(Fixly.Repo, "SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "connected"})

      {:error, _reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", database: "unavailable"})
    end
  end
end
