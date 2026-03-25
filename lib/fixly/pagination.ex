defmodule Fixly.Pagination do
  @moduledoc """
  Generic cursor-based (keyset) pagination.

  Cursors encode `{sort_field_value, id}` as Base64 so they are opaque to clients.
  We fetch `limit + 1` rows and use the extra row to determine `has_more`.
  """

  import Ecto.Query
  alias Fixly.Repo

  @default_limit 30

  @doc """
  Paginate a query ordered by `inserted_at DESC, id DESC` (newest first).

  ## Options
    * `:cursor` — opaque cursor from a previous page (nil for first page)
    * `:limit`  — page size (default #{@default_limit})
  """
  def paginate_desc(queryable, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cursor = Keyword.get(opts, :cursor)

    queryable
    |> apply_cursor_desc(cursor)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^(limit + 1))
    |> Repo.all()
    |> build_page(limit, :desc)
  end

  @doc """
  Paginate a query ordered by `name ASC, id ASC` (alphabetical).

  ## Options
    * `:cursor` — opaque cursor from a previous page (nil for first page)
    * `:limit`  — page size (default #{@default_limit})
  """
  def paginate_asc(queryable, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cursor = Keyword.get(opts, :cursor)

    queryable
    |> apply_cursor_asc(cursor)
    |> order_by([r], asc: r.name, asc: r.id)
    |> limit(^(limit + 1))
    |> Repo.all()
    |> build_page(limit, :asc)
  end

  @doc "Decode a cursor string. Returns `{sort_value, id}` or nil."
  def decode_cursor(nil), do: nil

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         {:ok, term} <- safe_binary_to_term(decoded) do
      term
    else
      _ -> nil
    end
  end

  @doc "Encode a cursor from a sort value and id."
  def encode_cursor(sort_value, id) do
    {sort_value, id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end

  # --- Private ---

  defp apply_cursor_desc(query, nil), do: query

  defp apply_cursor_desc(query, cursor) do
    case decode_cursor(cursor) do
      {inserted_at, id} ->
        where(
          query,
          [r],
          r.inserted_at < ^inserted_at or
            (r.inserted_at == ^inserted_at and r.id < ^id)
        )

      _ ->
        query
    end
  end

  defp apply_cursor_asc(query, nil), do: query

  defp apply_cursor_asc(query, cursor) do
    case decode_cursor(cursor) do
      {name, id} ->
        where(
          query,
          [r],
          r.name > ^name or
            (r.name == ^name and r.id > ^id)
        )

      _ ->
        query
    end
  end

  defp build_page(rows, limit, direction) do
    has_more = length(rows) > limit
    entries = Enum.take(rows, limit)

    cursor =
      case List.last(entries) do
        nil ->
          nil

        last ->
          case direction do
            :desc -> encode_cursor(last.inserted_at, last.id)
            :asc -> encode_cursor(last.name, last.id)
          end
      end

    %{entries: entries, cursor: cursor, has_more: has_more}
  end

  defp safe_binary_to_term(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    _ -> :error
  end
end
