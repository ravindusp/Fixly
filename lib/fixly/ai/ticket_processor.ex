defmodule Fixly.AI.TicketProcessor do
  @moduledoc """
  Processes incoming tickets using Gemini AI to:
  - Categorize the ticket
  - Suggest priority
  - Match to existing assets or propose new ones
  - Normalize custom room/item names
  """

  require Logger

  alias Fixly.AI.Client
  alias Fixly.Tickets
  alias Fixly.Locations
  alias Fixly.Repo

  @tools [
    %{
      name: "suggest_category",
      description: "Suggest a maintenance category for this ticket based on the description.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "category" => %{
            "type" => "string",
            "enum" => ["hvac", "plumbing", "electrical", "structural", "appliance", "furniture", "it", "other"],
            "description" => "The maintenance category"
          },
          "confidence" => %{
            "type" => "number",
            "description" => "Confidence score 0.0 to 1.0"
          }
        },
        "required" => ["category", "confidence"]
      }
    },
    %{
      name: "suggest_priority",
      description: "Suggest a priority level based on the issue description and urgency indicators.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "priority" => %{
            "type" => "string",
            "enum" => ["emergency", "high", "medium", "low"],
            "description" => "The suggested priority"
          },
          "confidence" => %{
            "type" => "number",
            "description" => "Confidence score 0.0 to 1.0"
          },
          "reasoning" => %{
            "type" => "string",
            "description" => "Brief explanation of why this priority was chosen"
          }
        },
        "required" => ["priority", "confidence", "reasoning"]
      }
    },
    %{
      name: "propose_asset",
      description: "Propose creating a new asset for this location based on the ticket description. Use this when no existing asset matches.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "name" => %{
            "type" => "string",
            "description" => "Name of the asset (e.g., 'AC Unit', 'Ceiling Fan', 'Toilet')"
          },
          "category" => %{
            "type" => "string",
            "enum" => ["hvac", "plumbing", "electrical", "structural", "appliance", "furniture", "it", "other"],
            "description" => "Asset category"
          },
          "confidence" => %{
            "type" => "number",
            "description" => "Confidence score 0.0 to 1.0"
          },
          "reasoning" => %{
            "type" => "string",
            "description" => "Why this asset should be created"
          }
        },
        "required" => ["name", "category", "confidence", "reasoning"]
      }
    },
    %{
      name: "link_to_existing_asset",
      description: "Link this ticket to an existing asset that matches the described issue.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "asset_id" => %{
            "type" => "string",
            "description" => "The UUID of the existing asset to link to"
          },
          "confidence" => %{
            "type" => "number",
            "description" => "Confidence score 0.0 to 1.0"
          }
        },
        "required" => ["asset_id", "confidence"]
      }
    }
  ]

  @doc "Process a ticket with AI to categorize, suggest priority, and discover assets."
  def process(ticket_id) do
    ticket = Tickets.get_ticket!(ticket_id)

    # Build context
    context = build_context(ticket)
    system_prompt = build_system_prompt(context)

    user_message = """
    New maintenance ticket submitted:

    Description: #{ticket.description}
    Location: #{context.location_name}
    Custom item mentioned: #{ticket.custom_item_name || "none"}
    Category selected by user: #{ticket.category || "not selected"}

    Existing assets at this location: #{format_assets(context.existing_assets)}
    Assets in similar locations: #{format_assets(context.similar_assets)}

    Please analyze this ticket and:
    1. Suggest a category if not already set
    2. Suggest a priority level
    3. Either link to an existing asset or propose a new one
    """

    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_message}
    ]

    case Client.chat(messages, @tools) do
      {:ok, :tool_calls, calls} ->
        process_tool_calls(ticket, calls)

      {:ok, :text, _text} ->
        Logger.info("AI returned text instead of tool calls for ticket #{ticket.reference_number}")
        :ok

      {:error, :no_api_key} ->
        Logger.debug("Skipping AI processing — no API key configured")
        :ok

      {:error, reason} ->
        Logger.error("AI processing failed for ticket #{ticket.reference_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- Context Building ---

  defp build_context(ticket) do
    location = ticket.location
    location_name = if location, do: build_breadcrumb(location), else: "Unknown"

    # Get existing assets at this location
    existing_assets =
      if location do
        try do
          Fixly.Assets.list_assets_for_location(location.id)
        rescue
          _ -> []
        end
      else
        []
      end

    # Get assets in sibling/similar locations
    similar_assets =
      if location && location.parent_id do
        try do
          siblings = Locations.get_children(location.parent_id)
          siblings
          |> Enum.reject(&(&1.id == location.id))
          |> Enum.flat_map(fn sibling ->
            try do
              Fixly.Assets.list_assets_for_location(sibling.id)
            rescue
              _ -> []
            end
          end)
          |> Enum.uniq_by(& &1.name)
        rescue
          _ -> []
        end
      else
        []
      end

    %{
      location_name: location_name,
      existing_assets: existing_assets,
      similar_assets: similar_assets
    }
  end

  defp build_breadcrumb(nil), do: "Unknown"
  defp build_breadcrumb(location) do
    location = Repo.preload(location, :parent)
    case location.parent do
      nil -> location.name
      parent -> build_breadcrumb(parent) <> " > " <> location.name
    end
  end

  defp build_system_prompt(context) do
    """
    You are an AI assistant for a maintenance management system (CMMS).
    Your job is to analyze incoming maintenance tickets and:

    1. Categorize them (hvac, plumbing, electrical, structural, appliance, furniture, it, other)
    2. Suggest a priority (emergency, high, medium, low) based on urgency:
       - emergency: safety hazard, flooding, no electricity, fire risk
       - high: major disruption like AC broken in hot weather, significant leak
       - medium: inconvenience like appliance malfunction, minor leak, door issue
       - low: cosmetic issues, paint, minor wear
    3. Match to existing assets or propose new ones

    Current location: #{context.location_name}
    Known assets here: #{format_assets(context.existing_assets)}
    Assets in nearby locations: #{format_assets(context.similar_assets)}

    ALWAYS use the tool functions to respond. Call suggest_category, suggest_priority,
    and either link_to_existing_asset or propose_asset.
    """
  end

  defp format_assets([]), do: "none registered yet"
  defp format_assets(assets) do
    assets
    |> Enum.map(fn a -> "#{a.name} (#{a.category}, id: #{a.id})" end)
    |> Enum.join(", ")
  end

  # --- Tool Call Processing ---

  defp process_tool_calls(ticket, calls) do
    Enum.each(calls, fn call ->
      process_single_call(ticket, call)
    end)

    :ok
  end

  defp process_single_call(ticket, %{name: "suggest_category", args: args}) do
    confidence = args["confidence"] || 0.0
    category = args["category"]

    if confidence >= 0.9 && is_nil(ticket.category) do
      # Auto-apply high-confidence category
      Tickets.update_ticket(ticket, %{category: category})
      create_suggestion(ticket, "category", args, confidence, "auto_applied")
    else
      create_suggestion(ticket, "category", args, confidence, "pending")
    end
  end

  defp process_single_call(ticket, %{name: "suggest_priority", args: args}) do
    confidence = args["confidence"] || 0.0

    # Priority is always a suggestion, never auto-applied (admin's decision)
    create_suggestion(ticket, "priority", args, confidence, "pending")
  end

  defp process_single_call(ticket, %{name: "propose_asset", args: args}) do
    confidence = args["confidence"] || 0.0
    create_suggestion(ticket, "create_asset", args, confidence, "pending")
  end

  defp process_single_call(ticket, %{name: "link_to_existing_asset", args: args}) do
    confidence = args["confidence"] || 0.0

    if confidence >= 0.9 do
      # Auto-link high-confidence matches
      try do
        Fixly.Assets.link_ticket_to_asset(ticket.id, args["asset_id"], "ai")
        create_suggestion(ticket, "link_asset", args, confidence, "auto_applied")
      rescue
        _ -> create_suggestion(ticket, "link_asset", args, confidence, "pending")
      end
    else
      create_suggestion(ticket, "link_asset", args, confidence, "pending")
    end
  end

  defp process_single_call(_ticket, %{name: name}) do
    Logger.warning("Unknown AI tool call: #{name}")
  end

  defp create_suggestion(ticket, type, data, confidence, status) do
    try do
      Fixly.AI.create_suggestion(%{
        ticket_id: ticket.id,
        suggestion_type: type,
        suggested_data: data,
        confidence: confidence,
        reasoning: data["reasoning"],
        status: status
      })
    rescue
      e -> Logger.error("Failed to create AI suggestion: #{inspect(e)}")
    end
  end
end
