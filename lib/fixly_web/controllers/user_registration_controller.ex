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
        |> put_flash(:info, "Account created successfully. Please log in.")
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
