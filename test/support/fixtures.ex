defmodule Polybot.Fixtures do
  @moduledoc """
  Test data builders: raw Gamma API markets, parsed markets, Claude responses and positions.
  """

  alias Polybot.Repo
  alias Polybot.Trading.Position

  @doc "A market as returned by the Gamma API (prices as JSON-encoded strings)."
  def gamma_market(id, question, prices, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "question" => question,
        "active" => true,
        "closed" => false,
        "volume" => "100000",
        "liquidity" => "5000",
        "endDate" => "2026-12-31T00:00:00Z",
        "outcomes" => ~s(["Yes","No"]),
        "outcomePrices" => prices && Jason.encode!(prices)
      },
      overrides
    )
  end

  @doc "A market as produced by `Polybot.Polymarket.Gamma` after parsing."
  def market(yes_price, no_price, overrides \\ %{}) do
    Map.merge(
      %{
        id: "m1",
        question: "Will the election go to a runoff?",
        volume: 100_000.0,
        liquidity: 5_000.0,
        end_date: "2026-12-31T00:00:00Z",
        yes_price: yes_price && Decimal.new(yes_price),
        no_price: no_price && Decimal.new(no_price)
      },
      overrides
    )
  end

  @doc "An Anthropic Messages API response with a single text block."
  def claude_response(text), do: %{"content" => [%{"type" => "text", "text" => text}]}

  def claude_json(fields), do: claude_response(Jason.encode!(fields))

  @doc "A decision as produced by `Polybot.AI.Analyst`."
  def decision(overrides \\ %{}) do
    Map.merge(
      %{
        market_id: "m1",
        question: "Will the election go to a runoff?",
        market_price: Decimal.new("0.40"),
        no_price: Decimal.new("0.60"),
        our_probability: Decimal.new("0.60"),
        confidence: "high",
        edge: Decimal.new("0.20"),
        action: "buy_yes",
        reasoning: "test"
      },
      overrides
    )
  end

  def insert_position!(overrides \\ %{}) do
    %Position{}
    |> Position.changeset(
      Map.merge(
        %{
          market_id: "m1",
          question: "q",
          action: "buy_yes",
          entry_price: Decimal.new("0.40"),
          shares: Decimal.new("250"),
          cost: Decimal.new("100"),
          status: "open"
        },
        overrides
      )
    )
    |> Repo.insert!()
  end
end
