defmodule FixlyWeb.UserRegistrationController do
  use FixlyWeb, :controller

  alias Fixly.Accounts
  alias Fixly.Accounts.User

  plug :put_layout, html: {FixlyWeb.Layouts, :auth}

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, _user} ->
        conn
        |> redirect(to: ~p"/users/pending")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def pending(conn, _params) do
    render(conn, :pending)
  end
end
