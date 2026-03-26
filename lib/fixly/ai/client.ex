defmodule Fixly.AI.Client do
  @moduledoc """
  HTTP client for Google Gemini API (gemini-3-flash-preview).
  Handles tool-calling for asset discovery, ticket categorization, and priority suggestion.
  """

  require Logger

  @model "gemini-3-flash-preview"
  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @doc "Send a message to Gemini with tools and get back tool calls."
  def chat(messages, tools \\ [], opts \\ []) do
    api_key = api_key()

    unless api_key do
      Logger.warning("Gemini API key not configured, skipping AI processing")
      {:error, :no_api_key}
    else
      body = build_request_body(messages, tools, opts)

      url = "#{@base_url}/models/#{@model}:generateContent"
      headers = [{"x-goog-api-key", api_key}]

      case Req.post(url, json: body, headers: headers, receive_timeout: 30_000) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_response(response_body)

        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Gemini API error #{status}: #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          Logger.error("Gemini API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  # --- Request Building ---

  defp build_request_body(messages, tools, opts) do
    body = %{
      "contents" => Enum.map(messages, &format_message/1),
      "generationConfig" => %{
        "temperature" => Keyword.get(opts, :temperature, 0.2),
        "maxOutputTokens" => Keyword.get(opts, :max_tokens, 1024)
      }
    }

    if tools != [] do
      Map.put(body, "tools", [%{"functionDeclarations" => Enum.map(tools, &format_tool/1)}])
    else
      body
    end
  end

  defp format_message(%{role: role, content: content}) do
    gemini_role = if role == :system, do: "user", else: to_string(role)
    %{"role" => gemini_role, "parts" => [%{"text" => content}]}
  end

  defp format_tool(%{name: name, description: description, parameters: parameters}) do
    %{
      "name" => name,
      "description" => description,
      "parameters" => parameters
    }
  end

  # --- Response Parsing ---

  defp parse_response(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    # Check for function calls
    function_calls =
      parts
      |> Enum.filter(&Map.has_key?(&1, "functionCall"))
      |> Enum.map(fn %{"functionCall" => %{"name" => name, "args" => args}} ->
        %{name: name, args: args}
      end)

    if function_calls != [] do
      {:ok, :tool_calls, function_calls}
    else
      # Extract text response
      text =
        parts
        |> Enum.filter(&Map.has_key?(&1, "text"))
        |> Enum.map(& &1["text"])
        |> Enum.join("")

      {:ok, :text, text}
    end
  end

  defp parse_response(other) do
    Logger.warning("Unexpected Gemini response format: #{inspect(other)}")
    {:error, :unexpected_response}
  end

  defp api_key do
    Application.get_env(:fixly, :gemini_api_key) ||
      System.get_env("GEMINI_API_KEY")
  end
end
