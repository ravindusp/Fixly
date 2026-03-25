defmodule Fixly.Invoices do
  @moduledoc "Context for managing invoices and time entries."

  import Ecto.Query
  alias Fixly.Repo
  alias Fixly.Invoices.{Invoice, TimeEntry}

  # --- Invoices ---

  def get_invoice!(id) do
    Invoice
    |> Repo.get!(id)
    |> Repo.preload([:ticket, :organization, :uploaded_by_user, :approved_by_user])
  end

  def get_invoice(id), do: Repo.get(Invoice, id)

  @doc "List invoices for an organization."
  def list_invoices(org_id, opts \\ []) do
    Invoice
    |> where([i], i.organization_id == ^org_id)
    |> maybe_filter_invoice_status(opts[:status])
    |> order_by([i], [desc: i.inserted_at])
    |> preload([:ticket, :uploaded_by_user])
    |> Repo.all()
  end

  @doc "List invoices for a specific ticket."
  def list_invoices_for_ticket(ticket_id) do
    Invoice
    |> where([i], i.ticket_id == ^ticket_id)
    |> order_by([i], [desc: i.inserted_at])
    |> preload([:uploaded_by_user, :approved_by_user])
    |> Repo.all()
  end

  def create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  def update_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end

  def delete_invoice(%Invoice{} = invoice) do
    Repo.delete(invoice)
  end

  @doc "Approve an invoice."
  def approve_invoice(%Invoice{} = invoice, approved_by_user_id) do
    invoice
    |> Invoice.changeset(%{
      status: "approved",
      approved_by: approved_by_user_id,
      approved_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  # --- Time Entries ---

  def get_time_entry!(id) do
    TimeEntry
    |> Repo.get!(id)
    |> Repo.preload([:ticket, :user])
  end

  def get_time_entry(id), do: Repo.get(TimeEntry, id)

  @doc "List time entries for a ticket."
  def list_time_entries_for_ticket(ticket_id) do
    TimeEntry
    |> where([te], te.ticket_id == ^ticket_id)
    |> order_by([te], [desc: te.date])
    |> preload([:user])
    |> Repo.all()
  end

  @doc "List time entries for a user."
  def list_time_entries_for_user(user_id) do
    TimeEntry
    |> where([te], te.user_id == ^user_id)
    |> order_by([te], [desc: te.date])
    |> preload([:ticket])
    |> Repo.all()
  end

  def create_time_entry(attrs) do
    %TimeEntry{}
    |> TimeEntry.changeset(attrs)
    |> Repo.insert()
  end

  def update_time_entry(%TimeEntry{} = time_entry, attrs) do
    time_entry
    |> TimeEntry.changeset(attrs)
    |> Repo.update()
  end

  def delete_time_entry(%TimeEntry{} = time_entry) do
    Repo.delete(time_entry)
  end

  # --- Cost Aggregation ---

  @doc "Total invoice amount for a ticket."
  def total_invoice_amount_for_ticket(ticket_id) do
    Invoice
    |> where([i], i.ticket_id == ^ticket_id and i.status == "approved")
    |> Repo.aggregate(:sum, :total_amount) || Decimal.new(0)
  end

  @doc "Total labor cost for a ticket (hours * hourly_rate)."
  def total_labor_cost_for_ticket(ticket_id) do
    TimeEntry
    |> where([te], te.ticket_id == ^ticket_id and not is_nil(te.hourly_rate))
    |> select([te], sum(te.hours * te.hourly_rate))
    |> Repo.one() || Decimal.new(0)
  end

  @doc "Total hours logged for a ticket."
  def total_hours_for_ticket(ticket_id) do
    TimeEntry
    |> where([te], te.ticket_id == ^ticket_id)
    |> Repo.aggregate(:sum, :hours) || Decimal.new(0)
  end

  # --- Helpers ---

  defp maybe_filter_invoice_status(query, nil), do: query
  defp maybe_filter_invoice_status(query, status), do: where(query, [i], i.status == ^status)
end
