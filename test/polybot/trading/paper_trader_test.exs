defmodule Polybot.Trading.PaperTraderTest do
  # Not async: opening a position takes an app-wide advisory lock, which inside the SQL
  # sandbox is held until the test ends and would serialize async tests anyway.
  use Polybot.DataCase, async: false

  @moduletag :capture_log

  import Polybot.Fixtures
  alias Polybot.Trading.{Decision, PaperTrader, Position}

  describe "open_position/1 pricing" do
    test "buy_yes is opened at the YES price" do
      assert {:ok, position} = PaperTrader.open_position(decision(%{action: "buy_yes"}))

      assert Decimal.equal?(position.entry_price, "0.40")
      assert Decimal.equal?(position.cost, "100")
      assert Decimal.equal?(position.shares, "250")
    end

    test "buy_no is opened at the NO price, not the YES price" do
      assert {:ok, position} =
               PaperTrader.open_position(decision(%{action: "buy_no", edge: Decimal.new("-0.2")}))

      assert Decimal.equal?(position.entry_price, "0.60")
      assert Decimal.equal?(position.shares, "166.66666667")
    end

    test "refuses to open without a valid price" do
      assert {:error, :no_valid_price} =
               PaperTrader.open_position(decision(%{action: "buy_no", no_price: nil}))

      assert {:error, :no_valid_price} =
               PaperTrader.open_position(decision(%{market_price: Decimal.new(0)}))

      assert Repo.aggregate(Position, :count) == 0
    end
  end

  describe "open_position/1 risk limits" do
    test "one open position per market" do
      assert {:ok, _} = PaperTrader.open_position(decision())
      assert {:error, :already_open} = PaperTrader.open_position(decision())
    end

    test "a market can be traded again after its position is closed" do
      {:ok, position} = PaperTrader.open_position(decision())
      position |> Position.changeset(%{status: "closed"}) |> Repo.update!()

      assert {:ok, _} = PaperTrader.open_position(decision())
    end

    test "at most 5 open positions" do
      for i <- 1..5,
          do: assert({:ok, _} = PaperTrader.open_position(decision(%{market_id: "m#{i}"})))

      assert {:error, :max_open_positions} =
               PaperTrader.open_position(decision(%{market_id: "m6"}))

      assert Repo.aggregate(Position, :count) == 5
    end

    test "closed positions don't count towards the limits" do
      for i <- 1..5, do: insert_position!(%{market_id: "old#{i}", status: "closed"})

      assert {:ok, _} = PaperTrader.open_position(decision())
    end

    test "total exposure is capped at 50% of capital" do
      # Two large legacy positions already use $450 of the $500 exposure budget.
      insert_position!(%{market_id: "big1", cost: Decimal.new("300")})
      insert_position!(%{market_id: "big2", cost: Decimal.new("150")})

      assert {:error, :max_exposure} = PaperTrader.open_position(decision())
    end
  end

  describe "process_decision/2" do
    test "stores the decision with its cycle and opens a position" do
      assert {:ok, _} = PaperTrader.process_decision(decision(), 7)

      assert [%Decision{cycle: 7, action: "buy_yes"}] = Repo.all(Decision)
      assert Repo.aggregate(Position, :count) == 1
    end

    test "does not trade when the edge is below 10%" do
      PaperTrader.process_decision(decision(%{edge: Decimal.new("0.099")}), 1)

      assert Repo.aggregate(Decision, :count) == 1
      assert Repo.aggregate(Position, :count) == 0
    end

    test "does not trade on pass" do
      PaperTrader.process_decision(decision(%{action: "pass"}), 1)

      assert Repo.aggregate(Position, :count) == 0
    end
  end
end
