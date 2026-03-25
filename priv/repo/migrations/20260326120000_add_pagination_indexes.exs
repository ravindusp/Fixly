defmodule Fixly.Repo.Migrations.AddPaginationIndexes do
  use Ecto.Migration

  def change do
    # Cursor-based pagination for tickets (DESC by inserted_at)
    create index(:tickets, [:organization_id, :inserted_at, :id],
      name: :tickets_org_cursor_desc,
      comment: "Cursor-based pagination for ticket lists"
    )

    # Cursor-based pagination for assets (ASC by name)
    create index(:assets, [:organization_id, :name, :id],
      name: :assets_org_cursor_asc,
      comment: "Cursor-based pagination for asset lists"
    )

    # Dashboard overdue query optimization
    create index(:tickets, [:organization_id, :status],
      where: "sla_breached = true",
      name: :tickets_org_sla_breached_partial,
      comment: "Partial index for dashboard overdue tickets query"
    )
  end
end
