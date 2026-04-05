defmodule Polybot.AI.Analyst do
  @moduledoc """
  Claude-powered decision engine.
  Analyzes a market and returns probability estimate + trading decision.
  """

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"

  @doc """
  Analyze a market and return a decision.
  Returns {:ok, decision} or {:error, reason}
  """
  def analyze(market) do
    prompt = build_prompt(market)

    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]

    body = %{
      model: @model,
      max_tokens: 1024,
      messages: [
        %{role: "user", content: prompt}
      ]
    }

    case Req.post(@anthropic_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        parse_response(response, market)

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(market) do
    """
    You are an expert prediction market analyst. Analyze this market and estimate the true probability.

    Market: #{market.question}
    Current YES price: #{market.yes_price} (implies #{round(market.yes_price * 100)}% probability)
    Current NO price: #{market.no_price}
    Volume: $#{round(market.volume)}
    Liquidity: $#{round(market.liquidity)}
    End date: #{market.end_date}

    Based on your knowledge, what is the TRUE probability of YES?
    Consider: current events, base rates, market sentiment.

    Respond ONLY with a valid JSON object, no explanation, no markdown:
    {"probability": 0.65, "confidence": "medium", "edge": 0.10, "reasoning": "brief explanation", "action": "buy_yes"}

    Rules:
    - probability: float 0.0-1.0
    - confidence: "low", "medium", or "high"
    - edge: your_probability - market_yes_price (positive = buy YES, negative = buy NO)
    - action: "buy_yes", "buy_no", or "pass" (pass if edge < 0.10 or confidence is low)
    """
  end

  defp parse_response(response, market) do
  text = response
    |> get_in(["content", Access.at(0), "text"])
    |> String.trim()
    |> String.replace(~r/```json\n?/, "")
    |> String.replace(~r/```\n?/, "")
    |> String.trim()

  case Jason.decode(text) do
    {:ok, data} ->
      decision = %{
        market_id: market.id,
        question: market.question,
        market_price: market.yes_price,
        our_probability: data["probability"],
        confidence: data["confidence"],
        edge: data["edge"],
        action: data["action"],
        reasoning: data["reasoning"]
      }
      {:ok, decision}

    {:error, _} ->
      {:error, "Failed to parse Claude response: #{text}"}
  end
end

  defp api_key do
    System.get_env("ANTHROPIC_API_KEY") || raise "ANTHROPIC_API_KEY not set"
  end
end