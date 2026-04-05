defmodule Polybot.Trading.PaperTrader do
  @moduledoc """
  Paper trading engine. Records decisions and simulates trades without real money.
  """
  require Logger
  alias Polybot.Repo
  alias Polybot.Trading.{Decision, Position}

  @capital 1000.0
  @max_position_pct 0.10
  @min_edge 0.10

  def process_decision(decision, cycle \\ 0) do
    # Save decision to DB
    save_decision(decision, cycle)

    # Open position if action is buy
    if decision.action in ["buy_yes", "buy_no"] and
       abs(decision.edge) >= @min_edge do
      open_position(decision)
    end
  end

  def save_decision(decision, cycle) do
    %Decision{}
    |> Decision.changeset(%{
      market_id: decision.market_id,
      question: decision.question,
      market_price: decision.market_price,
      our_probability: decision.our_probability,
      confidence: decision.confidence,
      edge: decision.edge,
      action: decision.action,
      reasoning: decision.reasoning,
      cycle: cycle
    })
    |> Repo.insert()
    |> case do
      {:ok, d} ->
        Logger.debug("Decision saved: #{d.action} on #{d.market_id}")
      {:error, changeset} ->
        Logger.error("Failed to save decision: #{inspect(changeset.errors)}")
    end
  end

  def open_position(decision) do
    import Ecto.Query

    # Check if position already open for this market
    already_open = Repo.exists?(
      from p in Position,
      where: p.market_id == ^decision.market_id and p.status == "open"
    )

    if already_open do
      Logger.debug("Position already open for #{decision.market_id}, skipping")
    else
      position_size = @capital * @max_position_pct
      entry_price = decision.market_price
      shares = position_size / entry_price

      %Position{}
      |> Position.changeset(%{
        market_id: decision.market_id,
        question: decision.question,
        action: decision.action,
        entry_price: entry_price,
        shares: shares,
        cost: position_size,
        status: "open",
        paper: true
      })
      |> Repo.insert()
      |> case do
        {:ok, p} ->
          Logger.info("📝 Paper position opened: #{p.action} #{p.market_id} @ #{p.entry_price}, cost: $#{p.cost}")
        {:error, changeset} ->
          Logger.error("Failed to open position: #{inspect(changeset.errors)}")
      end
    end
  end

  def get_open_positions do
    import Ecto.Query
    Repo.all(from p in Position, where: p.status == "open" and p.paper == true)
  end

  def get_stats do
    import Ecto.Query

    total_decisions = Repo.aggregate(Decision, :count, :id)
    buy_decisions = Repo.aggregate(from(d in Decision, where: d.action != "pass"), :count, :id)
    open_positions = Repo.aggregate(from(p in Position, where: p.status == "open"), :count, :id)

    %{
      total_decisions: total_decisions,
      buy_decisions: buy_decisions,
      open_positions: open_positions
    }
  end
end