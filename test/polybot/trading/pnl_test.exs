defmodule Polybot.Trading.PnlTest do
  use ExUnit.Case, async: true

  alias Polybot.Trading.Pnl

  defp d(value), do: Decimal.new(value)

  describe "pnl_pct/2" do
    test "is relative to the entry price" do
      assert Decimal.equal?(Pnl.pnl_pct(d("0.40"), d("0.50")), d("0.25"))
      assert Decimal.equal?(Pnl.pnl_pct(d("0.40"), d("0.30")), d("-0.25"))
      assert Decimal.equal?(Pnl.pnl_pct(d("0.40"), d("0.40")), d("0"))
    end

    test "a resolved market at 0 means a full loss" do
      assert Decimal.equal?(Pnl.pnl_pct(d("0.40"), d("0")), d("-1"))
    end

    test "is exact where floats are not" do
      # (0.3 - 0.1) / 0.1 is 1.9999999999999998 with floats
      assert Decimal.equal?(Pnl.pnl_pct(d("0.1"), d("0.3")), d("2"))
    end
  end

  describe "pnl_usd/2" do
    test "scales the cost and rounds to 8 places" do
      assert Pnl.pnl_usd(d("100"), d("0.25")) == d("25.00000000")
      assert Pnl.pnl_usd(d("100"), Decimal.div(d("1"), d("3"))) == d("33.33333333")
    end
  end

  describe "close_reason/1" do
    test "take profit at +50% and above (inclusive)" do
      assert Pnl.close_reason(d("0.5")) == "take_profit"
      assert Pnl.close_reason(d("2")) == "take_profit"
    end

    test "stop loss at -40% and below (inclusive)" do
      assert Pnl.close_reason(d("-0.4")) == "stop_loss"
      assert Pnl.close_reason(d("-1")) == "stop_loss"
    end

    test "keeps the position open in between" do
      assert Pnl.close_reason(d("0.4999")) == nil
      assert Pnl.close_reason(d("0")) == nil
      assert Pnl.close_reason(d("-0.3999")) == nil
    end
  end
end
