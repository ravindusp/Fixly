defmodule Fixly.Locations do
  @moduledoc "Context for managing the location hierarchy tree."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Locations.Location

  def get_location!(id), do: Repo.get!(Location, id)

  def get_location(id), do: Repo.get(Location, id)

  @doc "Get a location by its QR code ID."
  def get_location_by_qr(qr_code_id) do
    Repo.get_by(Location, qr_code_id: qr_code_id)
  end

  @doc "Get the full tree for an organization, ordered by position."
  def get_tree(org_id) do
    Location
    |> where([l], l.organization_id == ^org_id)
    |> order_by([l], [l.depth, l.position, l.name])
    |> Repo.all()
    |> build_tree()
  end

  @doc "Get direct children of a location."
  def get_children(location_id) do
    Location
    |> where([l], l.parent_id == ^location_id)
    |> order_by([l], [l.position, l.name])
    |> Repo.all()
  end

  @doc "Get the root locations (top-level) for an org."
  def get_roots(org_id) do
    Location
    |> where([l], l.organization_id == ^org_id and is_nil(l.parent_id))
    |> order_by([l], [l.position, l.name])
    |> Repo.all()
  end

  @doc "Get ancestors (breadcrumb path) for a location."
  def get_ancestors(%Location{path: nil}), do: []

  def get_ancestors(%Location{path: path, organization_id: org_id}) do
    # Split the ltree path and look up each ancestor
    ancestor_paths =
      path
      |> String.split(".")
      |> Enum.scan(fn segment, acc -> acc <> "." <> segment end)

    # Include all ancestors by querying the path prefix
    Location
    |> where([l], l.organization_id == ^org_id)
    |> where([l], l.path in ^ancestor_paths or l.path == ^path)
    |> order_by([l], l.depth)
    |> Repo.all()
  end

  @doc "Get all descendants of a location using ltree."
  def get_descendants(%Location{path: path, organization_id: org_id}) do
    prefix = path <> "."

    Location
    |> where([l], l.organization_id == ^org_id)
    |> where([l], like(l.path, ^(prefix <> "%")))
    |> order_by([l], [l.depth, l.position, l.name])
    |> Repo.all()
  end

  @doc "Create a location under a parent (or as root if parent is nil).
  Child locations inherit the parent's GPS coordinates by default."
  def create_location(attrs) do
    parent_id = Map.get(attrs, :parent_id) || Map.get(attrs, "parent_id")

    {depth, attrs} =
      if parent_id do
        parent = get_location!(parent_id)

        # Inherit parent's GPS metadata if child doesn't have its own
        child_metadata = Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || %{}

        inherited_metadata =
          if child_metadata["gps_lat"] do
            child_metadata
          else
            parent_gps = Map.take(parent.metadata || %{}, ["gps_lat", "gps_lng"])
            Map.merge(parent_gps, child_metadata)
          end

        attrs = Map.put(attrs, :metadata, inherited_metadata)
        {parent.depth + 1, attrs}
      else
        {0, attrs}
      end

    result =
      %Location{}
      |> Location.changeset(attrs)
      |> Ecto.Changeset.put_change(:depth, depth)
      |> Repo.insert()

    # After insert, calculate and set the ltree path
    case result do
      {:ok, location} ->
        path = calculate_path(location)

        location
        |> Ecto.Changeset.change(%{path: path})
        |> Repo.update()

      error ->
        error
    end
  end

  @doc "Update a location's name, label, position, or metadata."
  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete a location and all its children (cascade)."
  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  @doc "Count total locations for an org."
  def count_locations(org_id) do
    Location
    |> where([l], l.organization_id == ^org_id)
    |> Repo.aggregate(:count)
  end

  @doc "Count locations with QR codes for an org."
  def count_qr_codes(org_id) do
    Location
    |> where([l], l.organization_id == ^org_id and not is_nil(l.qr_code_id))
    |> Repo.aggregate(:count)
  end

  @doc "Generate a unique QR code ID for a location."
  def generate_qr_code(%Location{} = location) do
    qr_code_id = Nanoid.generate(10, "0123456789abcdefghijklmnopqrstuvwxyz")

    location
    |> Ecto.Changeset.change(%{qr_code_id: qr_code_id})
    |> Repo.update()
  end

  # Build a nested tree structure from a flat list of locations
  defp build_tree(locations) do
    by_parent =
      Enum.group_by(locations, & &1.parent_id)

    roots = Map.get(by_parent, nil, [])
    Enum.map(roots, &attach_children(&1, by_parent))
  end

  defp attach_children(location, by_parent) do
    children = Map.get(by_parent, location.id, [])
    children_with_nested = Enum.map(children, &attach_children(&1, by_parent))
    %{location | children: children_with_nested}
  end

  # Calculate the ltree path from root to this location
  defp calculate_path(%Location{parent_id: nil} = location) do
    slugify(location.id)
  end

  defp calculate_path(%Location{parent_id: parent_id} = location) do
    parent = get_location!(parent_id)
    parent_path = parent.path || calculate_path(parent)
    parent_path <> "." <> slugify(location.id)
  end

  # Use a short form of the UUID for the ltree path segment
  # ltree labels can only contain alphanumeric chars and underscores
  defp slugify(id) when is_binary(id) do
    id
    |> String.replace("-", "_")
  end
end
