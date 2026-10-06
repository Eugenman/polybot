defmodule Polybot.Polymarket.Gamma do
  @moduledoc """
  Client for Polymarket Gamma API.
  Fetches and filters markets.
  """

  alias Polybot.Decimals

  @base_url "https://gamma-api.polymarket.com"

  @doc """
  Fetch active markets with minimum volume and liquidity.
  """
  def fetch_markets(opts \\ []) do
    min_volume = Keyword.get(opts, :min_volume, 10_000)
    limit = Keyword.get(opts, :limit, 50)

    case get("/markets", params: [active: true, closed: false, limit: limit]) do
      {:ok, %{status: 200, body: markets}} when is_list(markets) ->
        filtered =
          markets
          |> Enum.filter(&filter_market(&1, min_volume))
          |> Enum.map(&parse_market/1)

        {:ok, filtered}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_market(market_id) do
    case get("/markets/#{market_id}") do
      {:ok, %{status: 200, body: market}} when is_map(market) ->
        {:ok, parse_market(market)}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @political_keywords [
    "president",
    "election",
    "congress",
    "senate",
    "minister",
    "trump",
    "biden",
    "war",
    "ceasefire",
    "nuclear",
    "nato",
    "iran",
    "russia",
    "ukraine",
    "china",
    "taiwan",
    "israel",
    "fed",
    "rate",
    "gdp",
    "recession",
    "tariff",
    "trade"
  ]

  @sports_keywords [
    "nba",
    "nfl",
    "nhl",
    "fifa",
    "world cup",
    "finals",
    "championship",
    "super bowl",
    "playoff",
    "tournament",
    "win the"
  ]

  def fetch_political_and_sports_markets(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    min_volume = Keyword.get(opts, :min_volume, 50_000)

    case get("/markets", params: [active: true, closed: false, limit: limit]) do
      {:ok, %{status: 200, body: markets}} when is_list(markets) ->
        filtered =
          markets
          |> Enum.filter(&filter_market(&1, min_volume))
          |> Enum.filter(&is_relevant_market?/1)
          |> Enum.map(&parse_market/1)
          |> Enum.filter(&tradable?/1)

        {:ok, filtered}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extra Req options from config, e.g. a Req.Test plug in tests.
  defp get(path, opts \\ []) do
    req_options = Application.get_env(:polybot, __MODULE__, [])[:req_options] || []
    Req.get(@base_url <> path, opts ++ req_options)
  end

  @doc """
  A market is tradable when both YES and NO prices are known and strictly between 0 and 1.
  Prices of 0 or 1 mean the market is effectively resolved, and 0 would break P&L math.
  """
  def tradable?(%{yes_price: yes, no_price: no}), do: valid_price?(yes) and valid_price?(no)

  defp valid_price?(%Decimal{} = price) do
    Decimal.compare(price, 0) == :gt and Decimal.compare(price, 1) == :lt
  end

  defp valid_price?(_), do: false

  defp is_relevant_market?(market) do
    question = String.downcase(market["question"] || "")

    political = Enum.any?(@political_keywords, &String.contains?(question, &1))
    sports = Enum.any?(@sports_keywords, &String.contains?(question, &1))

    political || sports
  end

  defp filter_market(market, min_volume) do
    volume = market["volume"] |> parse_float()
    active = market["active"] == true
    closed = market["closed"] == true

    active && !closed && volume >= min_volume
  end

  defp parse_market(market) do
    {yes_price, no_price} =
      parse_outcome_prices(
        market["outcomes"],
        market["outcomePrices"]
      )

    %{
      id: market["id"],
      question: market["question"],
      volume: market["volume"] |> parse_float(),
      liquidity: market["liquidity"] |> parse_float(),
      end_date: market["endDate"],
      yes_price: yes_price,
      no_price: no_price,
      best_ask: Decimals.to_decimal(market["bestAsk"]),
      best_bid: Decimals.to_decimal(market["bestBid"]),
      condition_id: market["conditionId"]
    }
  end

  defp parse_outcome_prices(nil, _), do: {nil, nil}
  defp parse_outcome_prices(_, nil), do: {nil, nil}

  defp parse_outcome_prices(outcomes_json, prices_json) do
    with {:ok, outcomes} <- Jason.decode(outcomes_json),
         {:ok, prices} <- Jason.decode(prices_json) do
      pairs = Enum.zip(outcomes, prices)

      yes_price =
        pairs
        |> Enum.find_value(fn {o, p} ->
          if String.downcase(o) == "yes", do: Decimals.to_decimal(p)
        end)

      no_price =
        pairs
        |> Enum.find_value(fn {o, p} ->
          if String.downcase(o) == "no", do: Decimals.to_decimal(p)
        end)

      {yes_price, no_price}
    else
      _ -> {nil, nil}
    end
  end

  # Volume and liquidity are only used for filtering and display, so floats are fine here.
  # Prices go through Decimals.to_decimal/1.
  defp parse_float(nil), do: 0.0
  defp parse_float(val) when is_float(val), do: val

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(val) when is_integer(val), do: val * 1.0
end
