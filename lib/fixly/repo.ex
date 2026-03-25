defmodule Fixly.Repo do
  use Ecto.Repo,
    otp_app: :fixly,
    adapter: Ecto.Adapters.Postgres
end
