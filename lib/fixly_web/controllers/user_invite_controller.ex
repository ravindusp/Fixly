defmodule FixlyWeb.UserInviteController do
  use FixlyWeb, :controller

  alias Fixly.Accounts
  alias FixlyWeb.UserAuth

  plug :put_layout, html: {FixlyWeb.Layouts, :auth}

  def show(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_invite_token(token) do
      changeset = Accounts.change_user_password(user)

      conn
      |> assign(:user, user)
      |> assign(:token, token)
      |> assign(:changeset, changeset)
      |> render(:show)
    else
      conn
      |> put_flash(:error, "Invite link is invalid or has expired.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def accept(conn, %{"token" => token} = params) do
    require Logger
    Logger.error("INVITE ACCEPT called - token: #{token}, params keys: #{inspect(Map.keys(params))}")
    password_params = params["user"] || %{}

    case Accounts.accept_invite(token, password_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account set up successfully!")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        user = Accounts.get_user_by_invite_token(token)

        if user do
          conn
          |> assign(:user, user)
          |> assign(:token, token)
          |> assign(:changeset, changeset)
          |> render(:show)
        else
          conn
          |> put_flash(:error, "Invite link is invalid or has expired.")
          |> redirect(to: ~p"/users/log-in")
        end

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Invite link is invalid or has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
