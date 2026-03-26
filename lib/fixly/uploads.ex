defmodule Fixly.Uploads do
  @moduledoc "Helpers for resolving upload directories across environments."

  @doc "Returns the base upload directory path."
  def dir do
    if Application.get_env(:fixly, :upload_dir) do
      Application.get_env(:fixly, :upload_dir)
    else
      Path.join(["priv", "static", "uploads"])
    end
  end

  @doc "Returns the full path for a given upload subdirectory (e.g. \"logos\")."
  def dir(subdirectory) do
    Path.join(dir(), subdirectory)
  end
end
