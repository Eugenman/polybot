defmodule Polybot.Trading.Pnl do
  @moduledoc """
  Pure P&L math for a position, kept separate from DB and HTTP so it can be unit tested.
  All values are `Decimal`.
  """

  # close if profit >= 50%
  @take_profit Decimal.new("0.5")
  # close if loss <= -40%
  @stop_loss Decimal.new("-0.4")
  @money_scale 8

  @doc "Relative P&L of a position bought at `entry_price` and now worth `current_price`."
  def pnl_pct(entry_price, current_price) do
    current_price
    |> Decimal.sub(entry_price)
    |> Decimal.div(entry_price)
  end

  @doc "P&L in dollars for a position that cost `cost`, rounded to the DB scale."
  def pnl_usd(cost, pnl_pct) do
    cost |> Decimal.mult(pnl_pct) |> Decimal.round(@money_scale)
  end

  @doc """
  Why a position should be closed at this P&L: `"take_profit"`, `"stop_loss"` or `nil`.
  Both thresholds are inclusive.
  """
  def close_reason(pnl_pct) do
    cond do
      Decimal.compare(pnl_pct, @take_profit) != :lt -> "take_profit"
      Decimal.compare(pnl_pct, @stop_loss) != :gt -> "stop_loss"
      true -> nil
    end
  end
end
