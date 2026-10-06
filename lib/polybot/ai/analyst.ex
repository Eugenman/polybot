defmodule Polybot.AI.Analyst do
  @moduledoc """
  Claude-powered decision engine with two-stage analysis.
  Stage 1: Quick analysis to find edge > 10%
  Stage 2: Deep analysis with web search for promising markets
  """

  alias Polybot.Decimals
  alias Polybot.Polymarket.Gamma

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-haiku-4-5-20251001"
  @deep_analysis_min_edge Decimal.new("0.10")

  def analyze(market) do
    if Gamma.tradable?(market) do
      with {:ok, quick} <- quick_analysis(market) do
        if promising?(quick.edge), do: deep_analysis(market, quick), else: {:ok, quick}
      end
    else
      {:error, "Market #{market.id} has no tradable prices"}
    end
  end

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

    case Req.post(@anthropic_url, [json: body, headers: headers] ++ req_options()) do
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
    {"probability": 0.65, "confidence": "medium", "reasoning": "brief", "action": "buy_yes"}

    Rules:
    - probability: your estimate that the market resolves YES, float 0.0-1.0
    - confidence: "low", "medium", or "high"
    - action: "buy_yes" if probability is well above the YES price, "buy_no" if well below,
      otherwise "pass" (also pass if confidence is low)
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
    {"probability": 0.65, "confidence": "high", "reasoning": "detailed reasoning with news", "action": "buy_yes"}
    """
  end

  defp percent(price), do: price |> Decimal.mult(100) |> Decimal.round(0)

  defp parse_response({:ok, response}, market) do
    text =
      (response["content"] || [])
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

    with {:ok, data} when is_map(data) <- Jason.decode(json_text),
         {:ok, probability} <- validate_probability(data["probability"]) do
      # The model only estimates the probability; edge is calculated here, not trusted from the LLM.
      edge = Decimal.sub(probability, market.yes_price)

      reasoning =
        (data["reasoning"] || "")
        |> String.replace(~r/<cite[^>]*>/, "")
        |> String.replace(~r/<\/cite>/, "")

      {:ok,
       %{
         market_id: market.id,
         question: market.question,
         market_price: market.yes_price,
         no_price: market.no_price,
         our_probability: probability,
         confidence: data["confidence"],
         edge: edge,
         action: data["action"] |> normalize_action() |> consistent_with_edge(edge),
         reasoning: reasoning
       }}
    else
      {:error, :invalid_probability} ->
        {:error, "Claude returned no valid probability: #{text}"}

      _ ->
        {:error, "Failed to parse Claude response: #{text}"}
    end
  end

  defp parse_response({:error, reason}, _market), do: {:error, reason}

  defp validate_probability(value) do
    probability = Decimals.to_decimal(value)

    if probability && Decimal.compare(probability, 0) != :lt &&
         Decimal.compare(probability, 1) != :gt do
      {:ok, probability}
    else
      {:error, :invalid_probability}
    end
  end

  # Buying YES only makes sense when we think YES is underpriced (edge > 0), buying NO when
  # YES is overpriced (edge < 0). A contradicting action from the model becomes "pass".
  defp consistent_with_edge("buy_yes", edge),
    do: if(Decimal.positive?(edge), do: "buy_yes", else: "pass")

  defp consistent_with_edge("buy_no", edge),
    do: if(Decimal.negative?(edge), do: "buy_no", else: "pass")

  defp consistent_with_edge(action, _edge), do: action

  defp normalize_action("buy_yes"), do: "buy_yes"
  defp normalize_action("buy_no"), do: "buy_no"
  defp normalize_action("pass"), do: "pass"
  defp normalize_action("sell_yes"), do: "buy_no"
  defp normalize_action("sell_no"), do: "buy_yes"
  defp normalize_action("hold"), do: "pass"
  defp normalize_action(_), do: "pass"

  defp api_key do
    config()[:api_key] || System.get_env("ANTHROPIC_API_KEY") ||
      raise "ANTHROPIC_API_KEY not set"
  end

  # Extra Req options from config, e.g. a Req.Test plug in tests.
  defp req_options, do: config()[:req_options] || []

  defp config, do: Application.get_env(:polybot, __MODULE__, [])
end
