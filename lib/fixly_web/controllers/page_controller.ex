defmodule FixlyWeb.PageController do
  use FixlyWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/admin")
  end
end
