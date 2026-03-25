defmodule FixlyWeb.UserSessionHTML do
  use FixlyWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:fixly, Fixly.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
