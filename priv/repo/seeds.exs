# Seeds for development
#
#   mix run priv/repo/seeds.exs

alias Fixly.Repo
alias Fixly.Organizations.Organization
alias Fixly.Locations.Location
alias Fixly.Accounts.User

# --- Owner Organization (School) ---
{:ok, school} =
  %Organization{}
  |> Organization.changeset(%{name: "Hillcrest International School", type: "owner"})
  |> Repo.insert()

IO.puts("Created org: #{school.name} (#{school.id})")

# --- Contractor Companies ---
{:ok, quickfix} =
  %Organization{}
  |> Organization.changeset(%{
    name: "QuickFix Maintenance",
    type: "contractor",
    parent_org_id: school.id
  })
  |> Repo.insert()

{:ok, coolair} =
  %Organization{}
  |> Organization.changeset(%{
    name: "CoolAir HVAC Specialists",
    type: "contractor",
    parent_org_id: school.id
  })
  |> Repo.insert()

IO.puts("Created contractors: #{quickfix.name}, #{coolair.name}")

# --- Admin User ---
{:ok, admin} =
  %User{}
  |> User.email_changeset(%{email: "admin@hillcrest.edu"})
  |> User.password_changeset(%{password: "password123456"})
  |> User.profile_changeset(%{name: "Sarah Admin", role: "org_admin", organization_id: school.id})
  |> Repo.insert()

IO.puts("Created admin: #{admin.email}")

# --- Contractor Admin ---
{:ok, contractor_admin} =
  %User{}
  |> User.email_changeset(%{email: "manager@quickfix.com"})
  |> User.password_changeset(%{password: "password123456"})
  |> User.profile_changeset(%{
    name: "Mike Manager",
    role: "contractor_admin",
    organization_id: quickfix.id
  })
  |> Repo.insert()

IO.puts("Created contractor admin: #{contractor_admin.email}")

# --- Technicians ---
{:ok, tech1} =
  %User{}
  |> User.email_changeset(%{email: "john@hillcrest.edu"})
  |> User.password_changeset(%{password: "password123456"})
  |> User.profile_changeset(%{
    name: "John Technician",
    role: "technician",
    organization_id: school.id
  })
  |> Repo.insert()

{:ok, tech2} =
  %User{}
  |> User.email_changeset(%{email: "dave@quickfix.com"})
  |> User.password_changeset(%{password: "password123456"})
  |> User.profile_changeset(%{
    name: "Dave Handyman",
    role: "technician",
    organization_id: quickfix.id
  })
  |> Repo.insert()

IO.puts("Created technicians: #{tech1.name}, #{tech2.name}")

# --- Location Hierarchy ---
# Helper to create a location with auto-calculated path
create_location = fn attrs ->
  {:ok, loc} = Fixly.Locations.create_location(attrs)
  loc
end

# Top-level: Houses
house1 =
  create_location.(%{
    name: "Maple Lodge",
    label: "House",
    organization_id: school.id
  })

house2 =
  create_location.(%{
    name: "Oak Villa",
    label: "House",
    organization_id: school.id
  })

house3 =
  create_location.(%{
    name: "Pine Cottage",
    label: "House",
    organization_id: school.id
  })

# Rooms in House 1
_h1_living =
  create_location.(%{
    name: "Living Room",
    label: "Room",
    parent_id: house1.id,
    organization_id: school.id
  })

_h1_master =
  create_location.(%{
    name: "Master Bedroom",
    label: "Room",
    parent_id: house1.id,
    organization_id: school.id
  })

_h1_kitchen =
  create_location.(%{
    name: "Kitchen",
    label: "Room",
    parent_id: house1.id,
    organization_id: school.id
  })

_h1_bathroom =
  create_location.(%{
    name: "Bathroom",
    label: "Room",
    parent_id: house1.id,
    organization_id: school.id
  })

# Rooms in House 2
_h2_living =
  create_location.(%{
    name: "Living Room",
    label: "Room",
    parent_id: house2.id,
    organization_id: school.id
  })

_h2_bedroom =
  create_location.(%{
    name: "Bedroom",
    label: "Room",
    parent_id: house2.id,
    organization_id: school.id
  })

# Top-level: Academic Building
building1 =
  create_location.(%{
    name: "Academic Block A",
    label: "Building",
    organization_id: school.id
  })

wing_a =
  create_location.(%{
    name: "Wing A",
    label: "Wing",
    parent_id: building1.id,
    organization_id: school.id
  })

_classroom1 =
  create_location.(%{
    name: "Classroom 1",
    label: "Room",
    parent_id: wing_a.id,
    organization_id: school.id
  })

_classroom2 =
  create_location.(%{
    name: "Classroom 2",
    label: "Room",
    parent_id: wing_a.id,
    organization_id: school.id
  })

IO.puts("Created #{length(Repo.all(Location))} locations")

# Generate QR codes for houses and some rooms
{:ok, house1} = Fixly.Locations.generate_qr_code(house1)
{:ok, house2} = Fixly.Locations.generate_qr_code(house2)
{:ok, house3} = Fixly.Locations.generate_qr_code(house3)
{:ok, building1} = Fixly.Locations.generate_qr_code(building1)

IO.puts("Generated QR codes for: #{house1.name} (#{house1.qr_code_id}), #{house2.name} (#{house2.qr_code_id}), #{house3.name} (#{house3.qr_code_id}), #{building1.name} (#{building1.qr_code_id})")

# --- Sample Tickets ---
sample_tickets = [
  %{
    description: "AC unit in living room is making a loud grinding noise and not cooling properly",
    location_id: _h1_living.id,
    category: "hvac",
    status: "created",
    submitter_name: "James Wilson",
    submitter_email: "james@hillcrest.edu",
    submitter_phone: "+94771234567"
  },
  %{
    description: "Kitchen sink is leaking underneath, water pooling on floor",
    location_id: _h1_kitchen.id,
    category: "plumbing",
    status: "assigned",
    priority: "high",
    submitter_name: "Emily Chen",
    submitter_email: "emily@hillcrest.edu",
    assigned_to_org_id: quickfix.id,
    assigned_to_user_id: tech2.id
  },
  %{
    description: "Bathroom light switch sparking when turned on",
    location_id: _h1_bathroom.id,
    category: "electrical",
    status: "in_progress",
    priority: "emergency",
    submitter_name: "Sarah Admin",
    submitter_email: "admin@hillcrest.edu",
    assigned_to_user_id: tech1.id
  },
  %{
    description: "Bedroom window won't close properly, letting rain in",
    location_id: _h2_bedroom.id,
    category: "structural",
    status: "on_hold",
    priority: "medium",
    submitter_name: "David Park",
    submitter_email: "david@hillcrest.edu",
    assigned_to_org_id: quickfix.id,
    assigned_to_user_id: tech2.id
  },
  %{
    description: "Ceiling fan wobbling badly and making clicking sound",
    location_id: _h2_living.id,
    category: "electrical",
    status: "completed",
    priority: "low",
    submitter_name: "Maria Garcia",
    submitter_email: "maria@hillcrest.edu",
    assigned_to_user_id: tech1.id
  },
  %{
    description: "Projector in classroom not turning on, display completely dead",
    location_id: _classroom1.id,
    category: "it",
    status: "created",
    submitter_name: "Prof. Thompson",
    submitter_email: "thompson@hillcrest.edu"
  },
  %{
    description: "Air conditioning unit dripping water onto the floor near desks",
    location_id: _classroom2.id,
    category: "hvac",
    status: "triaged",
    priority: "medium",
    submitter_name: "Lisa Wang",
    submitter_email: "lisa@hillcrest.edu"
  },
  %{
    description: "Master bedroom door handle is loose and about to fall off",
    location_id: _h1_master.id,
    category: "structural",
    status: "assigned",
    priority: "low",
    submitter_name: "James Wilson",
    submitter_email: "james@hillcrest.edu",
    assigned_to_org_id: quickfix.id
  }
]

for attrs <- sample_tickets do
  {:ok, ticket} = Fixly.Tickets.create_ticket(Map.put(attrs, :organization_id, school.id))

  # Set priority and SLA if priority exists
  if attrs[:priority] do
    Fixly.Tickets.set_priority(ticket, attrs.priority)
  end

  # Update status and assignment if not "created"
  if attrs[:status] != "created" do
    updates = Map.take(attrs, [:status, :assigned_to_org_id, :assigned_to_user_id])
    Fixly.Tickets.update_ticket(ticket, updates)
  end
end

IO.puts("Created #{length(sample_tickets)} sample tickets")

IO.puts("\n✅ Seed complete!")
IO.puts("   Admin login: admin@hillcrest.edu / password123456")
IO.puts("   Contractor login: manager@quickfix.com / password123456")
IO.puts("   Scan QR for House 1: /r/#{house1.qr_code_id}")
