defmodule FixlyWeb.PageController do
  use FixlyWeb, :controller

  def home(conn, _params) do
    path =
      case conn.assigns[:current_scope] do
        %{user: %{role: role}} when role in ["super_admin", "org_admin"] -> ~p"/admin"
        %{user: %{role: "contractor_admin"}} -> ~p"/contractor/tickets"
        %{user: %{role: "technician"}} -> ~p"/tech/tickets"
        %{user: %{role: "resident"}} -> ~p"/my/tickets"
        _ -> ~p"/users/log-in"
      end

    redirect(conn, to: path)
  end
end
