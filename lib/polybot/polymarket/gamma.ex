defmodule Polybot.Polymarket.Gamma do
  @moduledoc """
  Client for Polymarket Gamma API.
  Fetches and filters markets.
  """

  @base_url "https://gamma-api.polymarket.com"

  @doc """
  Fetch active markets with minimum volume and liquidity.
  """
  def fetch_markets(opts \\ []) do
    min_volume = Keyword.get(opts, :min_volume, 10_000)
    limit = Keyword.get(opts, :limit, 50)

    case Req.get("#{@base_url}/markets", params: [
      active: true,
      closed: false,
      limit: limit
    ]) do
      {:ok, %{status: 200, body: markets}} when is_list(markets) ->
        filtered = markets
          |> Enum.filter(&filter_market(&1, min_volume))
          |> Enum.map(&parse_market/1)
        {:ok, filtered}

      {:ok, %{status: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_market(market, min_volume) do
    volume = market["volume"] |> parse_float()
    active = market["active"] == true
    closed = market["closed"] == true

    active && !closed && volume >= min_volume
  end

  defp parse_market(market) do
    {yes_price, no_price} = parse_outcome_prices(
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
      best_ask: market["bestAsk"] |> parse_float(),
      best_bid: market["bestBid"] |> parse_float(),
      condition_id: market["conditionId"]
    }
  end

  defp parse_outcome_prices(nil, _), do: {nil, nil}
  defp parse_outcome_prices(_, nil), do: {nil, nil}
  defp parse_outcome_prices(outcomes_json, prices_json) do
    with {:ok, outcomes} <- Jason.decode(outcomes_json),
         {:ok, prices} <- Jason.decode(prices_json) do
      pairs = Enum.zip(outcomes, prices)
      yes_price = pairs |> Enum.find_value(fn {o, p} ->
        if String.downcase(o) == "yes", do: parse_float(p)
      end)
      no_price = pairs |> Enum.find_value(fn {o, p} ->
        if String.downcase(o) == "no", do: parse_float(p)
      end)
      {yes_price, no_price}
    else
      _ -> {nil, nil}
    end
  end

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