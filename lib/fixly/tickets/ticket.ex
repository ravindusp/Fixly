defmodule Fixly.Tickets.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(created triaged assigned in_progress on_hold completed reviewed closed)
  @priorities ~w(emergency high medium low)
  @categories ~w(hvac plumbing electrical structural appliance furniture it other)

  schema "tickets" do
    field :reference_number, :string
    field :description, :string
    field :category, :string
    field :custom_location_name, :string
    field :custom_item_name, :string
    field :status, :string, default: "created"
    field :priority, :string
    field :submitter_name, :string
    field :submitter_email, :string
    field :submitter_phone, :string
    field :verified, :boolean, default: false
    field :metadata, :map, default: %{}

    # SLA fields
    field :sla_deadline, :utc_datetime
    field :sla_started_at, :utc_datetime
    field :sla_paused_at, :utc_datetime
    field :sla_total_paused_seconds, :integer, default: 0
    field :sla_breached, :boolean, default: false

    belongs_to :location, Fixly.Locations.Location
    belongs_to :organization, Fixly.Organizations.Organization
    belongs_to :submitter_user, Fixly.Accounts.User, foreign_key: :submitter_user_id
    belongs_to :assigned_to_org, Fixly.Organizations.Organization, foreign_key: :assigned_to_org_id
    belongs_to :assigned_to_user, Fixly.Accounts.User, foreign_key: :assigned_to_user_id

    has_many :attachments, Fixly.Tickets.TicketAttachment
    has_many :comments, Fixly.Tickets.TicketComment

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for public ticket submission (via QR scan)."
  def submission_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :description,
      :location_id,
      :organization_id,
      :category,
      :custom_location_name,
      :custom_item_name,
      :submitter_name,
      :submitter_email,
      :submitter_phone,
      :submitter_user_id,
      :verified
    ])
    |> validate_required([:description, :organization_id])
    |> validate_length(:description, min: 5, max: 5000)
  end

  @doc "Changeset for admin actions (triage, assign, priority)."
  def admin_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :status,
      :priority,
      :category,
      :assigned_to_org_id,
      :assigned_to_user_id,
      :location_id,
      :sla_deadline,
      :sla_started_at,
      :metadata
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities, message: "must be emergency, high, medium, or low")
  end

  @doc "Changeset for SLA timer operations."
  def sla_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :sla_deadline,
      :sla_started_at,
      :sla_paused_at,
      :sla_total_paused_seconds,
      :sla_breached
    ])
  end

  def statuses, do: @statuses
  def priorities, do: @priorities
  def categories, do: @categories
end
