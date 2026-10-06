defmodule Polybot.AI.Analyst do
  @moduledoc """
  Claude-powered decision engine with two-stage analysis.
  Stage 1: Quick analysis to find edge > 10%
  Stage 2: Deep analysis with web search for promising markets
  """

  alias Polybot.Decimals

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @deep_analysis_min_edge Decimal.new("0.10")

  def analyze(market) do
    case quick_analysis(market) do
      {:ok, quick} ->
        if promising?(quick.edge), do: deep_analysis(market, quick), else: {:ok, quick}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp promising?(nil), do: false

  defp promising?(edge) do
    Decimal.compare(Decimal.abs(edge), @deep_analysis_min_edge) != :lt
  end

  defp quick_analysis(market) do
    prompt = build_quick_prompt(market)

    call_claude(prompt, [])
    |> parse_response(market)
  end

  defp deep_analysis(market, quick) do
    prompt = build_deep_prompt(market, quick)

    tools = [
      %{
        "type" => "web_search_20250305",
        "name" => "web_search"
      }
    ]

    call_claude(prompt, tools)
    |> parse_response(market)
  end

  defp call_claude(prompt, tools) do
    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]

    body = %{
      model: @model,
      max_tokens: 1024,
      messages: [%{role: "user", content: prompt}]
    }

    body = if tools != [], do: Map.put(body, :tools, tools), else: body

    case Req.post(@anthropic_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_quick_prompt(market) do
    """
    You are a prediction market analyst. Give a quick probability estimate.

    Market: #{market.question}
    Current YES price: #{market.yes_price} (#{percent(market.yes_price)}%)
    Volume: $#{round(market.volume)}
    End date: #{market.end_date}

    Respond ONLY with valid JSON, no markdown:
    {"probability": 0.65, "confidence": "medium", "edge": 0.10, "reasoning": "brief", "action": "buy_yes"}

    Rules:
    - probability: float 0.0-1.0
    - confidence: "low", "medium", or "high"
    - edge: your_probability - market_yes_price
    - action: "buy_yes", "buy_no", or "pass" (pass if abs(edge) < 0.10 or confidence low)
    """
  end

  defp build_deep_prompt(market, quick) do
    """
    You are a prediction market analyst. Search for recent news and make a final decision.

    Market: #{market.question}
    Current YES price: #{market.yes_price} (#{percent(market.yes_price)}%)
    Volume: $#{round(market.volume)}
    End date: #{market.end_date}
    Quick estimate: #{quick.our_probability} (edge: #{quick.edge})

    Search for the latest news about this topic, then provide your final analysis.

    Respond ONLY with valid JSON, no markdown:
    {"probability": 0.65, "confidence": "high", "edge": 0.10, "reasoning": "detailed reasoning with news", "action": "buy_yes"}
    """
  end

  defp percent(price), do: price |> Decimal.mult(100) |> Decimal.round(0)

  defp parse_response({:ok, response}, market) do
    text =
      response
      |> get_in(["content"])
      |> Enum.filter(fn block -> block["type"] == "text" end)
      |> List.last()
      |> case do
        nil -> ""
        block -> block["text"] || ""
      end
      |> String.trim()

    json_text =
      case Regex.run(~r/\{[^{}]*"probability"[^{}]*\}/s, text) do
        [match] ->
          match

        _ ->
          text
          |> String.replace(~r/```json\n?/, "")
          |> String.replace(~r/```\n?/, "")
          |> String.trim()
      end

    case Jason.decode(json_text) do
      {:ok, data} ->
        action = normalize_action(data["action"])

        reasoning =
          (data["reasoning"] || "")
          |> String.replace(~r/<cite[^>]*>/, "")
          |> String.replace(~r/<\/cite>/, "")

        {:ok,
         %{
           market_id: market.id,
           question: market.question,
           market_price: market.yes_price,
           our_probability: Decimals.to_decimal(data["probability"]),
           confidence: data["confidence"],
           edge: Decimals.to_decimal(data["edge"]),
           action: action,
           reasoning: reasoning
         }}

      {:error, _} ->
        {:error, "Failed to parse Claude response: #{text}"}
    end
  end

  defp parse_response({:error, reason}, _market), do: {:error, reason}

  defp normalize_action("buy_yes"), do: "buy_yes"
  defp normalize_action("buy_no"), do: "buy_no"
  defp normalize_action("pass"), do: "pass"
  defp normalize_action("sell_yes"), do: "buy_no"
  defp normalize_action("sell_no"), do: "buy_yes"
  defp normalize_action("hold"), do: "pass"
  defp normalize_action(_), do: "pass"

  defp api_key do
    System.get_env("ANTHROPIC_API_KEY") || raise "ANTHROPIC_API_KEY not set"
  end
end
