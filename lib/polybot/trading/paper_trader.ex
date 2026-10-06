defmodule Polybot.Trading.PaperTrader do
  @moduledoc """
  Paper trading engine. Records decisions and simulates trades without real money.
  """
  require Logger
  import Ecto.Query
  alias Polybot.Repo
  alias Polybot.Trading.{Decision, Position}

  @capital Decimal.new("1000")
  @max_position_pct Decimal.new("0.10")
  @min_edge Decimal.new("0.10")
  @shares_scale 8

  # Risk limits. With a fixed 10% position size both limits bind at 5 positions;
  # the exposure limit still protects if position sizing becomes dynamic.
  @max_open_positions 5
  @max_exposure_pct Decimal.new("0.50")

  # Arbitrary app-wide key for pg_advisory_xact_lock: serializes opening positions.
  @open_position_lock 4_201_001

  def process_decision(decision, cycle \\ 0) do
    # Save decision to DB
    save_decision(decision, cycle)

    # Open position if action is buy
    if decision.action in ["buy_yes", "buy_no"] and edge_large_enough?(decision.edge) do
      open_position(decision)
    end
  end

  defp edge_large_enough?(nil), do: false
  defp edge_large_enough?(edge), do: Decimal.compare(Decimal.abs(edge), @min_edge) != :lt

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

  @doc """
  Opens a paper position if the risk limits allow it.

  Returns `{:ok, position}` or `{:error, reason}`, where reason is one of
  `:no_valid_price`, `:already_open`, `:max_open_positions`, `:max_exposure`
  or `{:invalid, errors}`.
  """
  def open_position(decision) do
    entry_price = entry_price(decision)

    result =
      if positive?(entry_price) do
        open_position_atomically(decision, entry_price)
      else
        {:error, :no_valid_price}
      end

    log_open_result(result, decision)
    result
  end

  # Limit checks and the insert run in one transaction under an advisory lock, so two
  # concurrent opens can't both see "4 of 5 positions" and both insert. The partial
  # unique index on open positions is the last line of defense against duplicates.
  defp open_position_atomically(decision, entry_price) do
    position_size = Decimal.mult(@capital, @max_position_pct)

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [@open_position_lock])

      with :ok <- check_limits(decision.market_id, position_size),
           {:ok, position} <- insert_position(decision, entry_price, position_size) do
        position
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp check_limits(market_id, position_size) do
    open = from(p in Position, where: p.status == "open")
    exposure = Repo.aggregate(open, :sum, :cost) || Decimal.new(0)
    max_exposure = Decimal.mult(@capital, @max_exposure_pct)

    cond do
      Repo.exists?(where(open, [p], p.market_id == ^market_id)) ->
        {:error, :already_open}

      Repo.aggregate(open, :count) >= @max_open_positions ->
        {:error, :max_open_positions}

      Decimal.compare(Decimal.add(exposure, position_size), max_exposure) == :gt ->
        {:error, :max_exposure}

      true ->
        :ok
    end
  end

  defp log_open_result({:ok, p}, _decision) do
    Logger.info(
      "📝 Paper position opened: #{p.action} #{p.market_id} @ #{p.entry_price}, cost: $#{p.cost}"
    )
  end

  defp log_open_result({:error, :already_open}, decision) do
    Logger.debug("Position already open for #{decision.market_id}, skipping")
  end

  defp log_open_result({:error, reason}, decision)
       when reason in [:max_open_positions, :max_exposure] do
    Logger.info("Risk limit #{reason} reached, not opening #{decision.market_id}")
  end

  defp log_open_result({:error, :no_valid_price}, decision) do
    Logger.warning("No valid #{decision.action} price for #{decision.market_id}, skipping")
  end

  defp log_open_result({:error, reason}, decision) do
    Logger.error("Failed to open position for #{decision.market_id}: #{inspect(reason)}")
  end

  # A YES position is bought at the YES price, a NO position at the NO price.
  # P&L is later tracked against the same side's price in PositionManager.
  defp entry_price(%{action: "buy_yes", market_price: yes_price}), do: yes_price
  defp entry_price(%{action: "buy_no"} = decision), do: Map.get(decision, :no_price)

  defp positive?(%Decimal{} = price), do: Decimal.positive?(price)
  defp positive?(_), do: false

  defp insert_position(decision, entry_price, position_size) do
    shares = position_size |> Decimal.div(entry_price) |> Decimal.round(@shares_scale)

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
      {:ok, position} ->
        {:ok, position}

      {:error, changeset} ->
        case changeset.errors[:market_id] do
          {_message, [constraint: :unique, constraint_name: _]} -> {:error, :already_open}
          _ -> {:error, {:invalid, changeset.errors}}
        end
    end
  end

  def get_open_positions do
    Repo.all(from p in Position, where: p.status == "open" and p.paper == true)
  end

  def get_stats do
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
