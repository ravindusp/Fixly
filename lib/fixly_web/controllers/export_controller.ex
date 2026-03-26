defmodule FixlyWeb.ExportController do
  @moduledoc "Handles CSV and PDF exports for tickets, analytics, and reports."

  use FixlyWeb, :controller

  import FixlyWeb.UserAuth, only: [require_role: 2]

  plug :require_role, ["org_admin", "super_admin"]

  alias Fixly.Tickets
  alias Fixly.Analytics.Engine

  @doc "Export all tickets as CSV."
  def tickets_csv(conn, _params) do
    user = conn.assigns.current_scope.user
    org_id = user.organization_id

    tickets = Tickets.list_tickets(org_id)

    csv_data =
      [["Reference", "Status", "Priority", "Category", "Location", "Description", "Submitter", "Assigned To", "Created At"]]
      |> Enum.concat(
        Enum.map(tickets, fn t ->
          [
            t.reference_number,
            t.status,
            t.priority || "",
            t.category || "",
            if(t.location, do: t.location.name, else: ""),
            t.description,
            t.submitter_name || "",
            if(t.assigned_to_user, do: t.assigned_to_user.name || t.assigned_to_user.email, else: if(t.assigned_to_org, do: t.assigned_to_org.name, else: "")),
            Calendar.strftime(t.inserted_at, "%Y-%m-%d %H:%M")
          ]
        end)
      )
      |> NimbleCSV.RFC4180.dump_to_iodata()

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"tickets_#{Date.to_string(Date.utc_today())}.csv\"")
    |> send_resp(200, csv_data)
  end

  @doc "Export analytics results as CSV."
  def analytics_csv(conn, params) do
    user = conn.assigns.current_scope.user
    org_id = user.organization_id

    location_ids =
      case params["location_ids"] do
        nil -> []
        ids when is_binary(ids) -> String.split(ids, ",", trim: true)
        ids when is_list(ids) -> ids
      end

    query =
      Engine.base_query(org_id)
      |> Engine.for_locations(location_ids)
      |> Engine.with_category(params["category"])
      |> Engine.with_priority(params["priority"])

    breakdown = Engine.breakdown_by_location(query)

    csv_data =
      [["Location", "Total Tickets", "Open", "Closed"]]
      |> Enum.concat(
        Enum.map(breakdown, fn row ->
          [row.location_name, row.ticket_count, row.open, row.closed]
        end)
      )
      |> NimbleCSV.RFC4180.dump_to_iodata()

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"analytics_#{Date.to_string(Date.utc_today())}.csv\"")
    |> send_resp(200, csv_data)
  end
end
