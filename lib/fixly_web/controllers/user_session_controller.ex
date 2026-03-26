defmodule FixlyWeb.UserSessionController do
  use FixlyWeb, :controller

  alias Fixly.Accounts
  alias FixlyWeb.UserAuth

  plug :put_layout, html: {FixlyWeb.Layouts, :auth}

  def new(conn, _params) do
    email = get_in(conn.assigns, [:current_scope, Access.key(:user), Access.key(:email)])
    form = Phoenix.Component.to_form(%{"email" => email}, as: "user")

    render(conn, :new, form: form)
  end

  # magic link login
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info =
      case params do
        %{"_action" => "confirmed"} -> "User confirmed successfully."
        _ -> "Welcome back!"
      end

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        case check_org_status(user) do
          :ok ->
            conn
            |> put_flash(:info, info)
            |> UserAuth.log_in_user(user, user_params)

          {:error, message} ->
            conn
            |> put_flash(:error, message)
            |> redirect(to: ~p"/users/log-in")
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> render(:new, form: Phoenix.Component.to_form(%{}, as: "user"))
    end
  end

  # email + password login
  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      case check_org_status(user) do
        :ok ->
          conn
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(user, user_params)

        {:error, message} ->
          form = Phoenix.Component.to_form(user_params, as: "user")

          conn
          |> put_flash(:error, message)
          |> render(:new, form: form)
      end
    else
      form = Phoenix.Component.to_form(user_params, as: "user")

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> render(:new, form: form)
    end
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    conn
    |> put_flash(:info, info)
    |> redirect(to: ~p"/users/log-in")
  end

  def confirm(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

      conn
      |> assign(:user, user)
      |> assign(:form, form)
      |> render(:confirm)
    else
      conn
      |> put_flash(:error, "Magic link is invalid or it has expired.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  # Check user and organization status before allowing login
  defp check_org_status(%{role: "super_admin"}), do: :ok

  defp check_org_status(%{deactivated_at: deactivated_at}) when not is_nil(deactivated_at) do
    {:error, "Your account has been deactivated. Contact your organization admin for assistance."}
  end

  defp check_org_status(%{organization_id: nil}), do: :ok

  defp check_org_status(user) do
    case Fixly.Organizations.get_organization(user.organization_id) do
      nil ->
        :ok

      %{status: "active"} ->
        :ok

      %{status: "pending"} ->
        {:error, "Your account is under review. You'll be able to log in once approved by our team."}

      %{status: "suspended"} ->
        {:error, "Your organization has been suspended. Please contact support for assistance."}

      _ ->
        {:error, "Unable to log in. Please contact support."}
    end
  end
end
