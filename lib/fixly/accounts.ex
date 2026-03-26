defmodule Fixly.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Fixly.Repo

  alias Fixly.Accounts.{User, UserToken, UserNotifier}

  @doc "List users (org_admin or technician) for a given organization."
  def list_users_by_organization(org_id) do
    User
    |> where([u], u.organization_id == ^org_id)
    |> where([u], u.role in ["org_admin", "technician"])
    |> order_by([u], u.name)
    |> Repo.all()
  end

  @doc "List active users for a given organization (all roles)."
  def list_all_users_by_organization(org_id) do
    User
    |> where([u], u.organization_id == ^org_id)
    |> where([u], is_nil(u.deactivated_at))
    |> order_by([u], u.name)
    |> Repo.all()
  end

  @doc "List deactivated users for a given organization."
  def list_deactivated_users_by_organization(org_id) do
    User
    |> where([u], u.organization_id == ^org_id)
    |> where([u], not is_nil(u.deactivated_at))
    |> order_by([u], [desc: u.deactivated_at])
    |> Repo.all()
  end

  @doc "List only active technicians for a given organization."
  def list_technicians_by_organization(org_id) do
    User
    |> where([u], u.organization_id == ^org_id and u.role == "technician")
    |> where([u], is_nil(u.deactivated_at))
    |> order_by([u], u.name)
    |> Repo.all()
  end

  @doc "Deactivate a user (soft-delete, keeps all data)."
  def deactivate_user(user_id) do
    user = Repo.get!(User, user_id)

    user
    |> Ecto.Changeset.change(%{deactivated_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  @doc "Reactivate a deactivated user."
  def reactivate_user(user_id) do
    user = Repo.get!(User, user_id)

    user
    |> Ecto.Changeset.change(%{deactivated_at: nil})
    |> Repo.update()
  end

  @doc "List pending invite tokens for a given organization."
  def list_pending_invites(org_id) do
    from(t in UserToken,
      join: u in User,
      on: t.user_id == u.id,
      where: t.context == "invite" and u.organization_id == ^org_id and is_nil(u.confirmed_at),
      select: %{
        id: t.id,
        user_id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        inserted_at: t.inserted_at
      },
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    changeset =
      %User{}
      |> User.registration_changeset(attrs)
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))

    role = Ecto.Changeset.get_field(changeset, :role)
    name = Ecto.Changeset.get_field(changeset, :name)

    if role in ["org_admin", "contractor_admin"] do
      org_type = if role == "org_admin", do: "owner", else: "contractor"

      Repo.transact(fn ->
        with {:ok, org} <-
               Fixly.Organizations.create_organization(%{
                 name: "#{name}'s Organization",
                 type: org_type,
                 status: "pending"
               }),
             {:ok, user} <-
               changeset
               |> Ecto.Changeset.put_change(:organization_id, org.id)
               |> Repo.insert() do
          {:ok, user}
        end
      end)
    else
      Repo.insert(changeset)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking registration changes.
  """
  def change_user_registration(user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, validate_unique: false, hash_password: false)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Fixly.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Fixly.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Invites

  @doc """
  Creates an invited user (no password) and generates an invite token.
  Returns `{:ok, {user, encoded_token}}` or `{:error, changeset}`.
  """
  def invite_user(attrs, _invited_by_user) do
    Repo.transact(fn ->
      changeset = User.invite_changeset(%User{}, attrs)

      with {:ok, user} <- Repo.insert(changeset) do
        {encoded_token, user_token} = UserToken.build_invite_token(user)
        Repo.insert!(user_token)
        {:ok, {user, encoded_token}}
      end
    end)
  end

  @doc """
  Resend an invite for an existing pending user. Deletes old invite tokens and creates a new one.
  Verifies the user belongs to the given organization.
  Returns `{:ok, {user, encoded_token}}` or `{:error, :not_found | :unauthorized | :already_confirmed}`.
  """
  def resend_invite(user_id, org_id) do
    user =
      from(u in User, where: u.id == ^user_id and u.organization_id == ^org_id)
      |> Repo.one()

    cond do
      is_nil(user) -> {:error, :unauthorized}
      user.confirmed_at != nil -> {:error, :already_confirmed}
      true ->
        # Delete old invite tokens
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "invite")
        |> Repo.delete_all()

        # Create new token
        {encoded_token, user_token} = UserToken.build_invite_token(user)
        Repo.insert!(user_token)
        {:ok, {user, encoded_token}}
    end
  end

  @doc """
  Gets a user by invite token. Returns the user or nil.
  """
  def get_user_by_invite_token(token) do
    with {:ok, query} <- UserToken.verify_invite_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Accepts an invite: sets password, confirms user, deletes invite token.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def accept_invite(token, password_attrs) do
    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_invite_token_query(token),
           {user, db_token} <- Repo.one(query) do
        user
        |> User.password_changeset(password_attrs)
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
        |> Repo.update()
        |> case do
          {:ok, user} ->
            Repo.delete!(db_token)
            {:ok, user}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        _ -> {:error, :invalid_token}
      end
    end)
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
