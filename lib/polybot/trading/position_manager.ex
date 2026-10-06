defmodule Polybot.Trading.PositionManager do
  @moduledoc """
  Manages open positions — updates P&L and closes positions.
  """
  require Logger
  import Ecto.Query
  alias Polybot.Repo
  alias Polybot.Trading.Position
  alias Polybot.Polymarket.Gamma

  # close if profit >= 50%
  @take_profit Decimal.new("0.5")
  # close if loss <= -40%
  @stop_loss Decimal.new("-0.4")
  @money_scale 8

  def update_positions do
    positions =
      Repo.all(
        from p in Position,
          where: p.status == "open" and p.paper == true
      )

    Logger.info("Updating #{length(positions)} open positions")

    Enum.each(positions, &update_position/1)
  end

  defp update_position(position) do
    with {:ok, market} <- Gamma.fetch_market(position.market_id),
         %Decimal{} = current_price <- current_price(market, position.action),
         true <- Decimal.positive?(position.entry_price) do
      apply_price(position, current_price)
    else
      {:error, reason} ->
        Logger.error("Failed to fetch market #{position.market_id}: #{inspect(reason)}")

      _ ->
        Logger.warning("No usable price for position #{position.id} (#{position.market_id})")
    end
  end

  # Unlike entry, the current price may be exactly 0 or 1: the market has resolved.
  defp current_price(market, "buy_yes"), do: market.yes_price
  defp current_price(market, "buy_no"), do: market.no_price
  defp current_price(_market, _action), do: nil

  # P&L update and closing happen in a single UPDATE, so a position can't end up
  # with new P&L but a stale status (or the other way around).
  defp apply_price(position, current_price) do
    pnl_pct = calculate_pnl(position, current_price)
    pnl_usd = pnl_usd(position, pnl_pct)
    close_reason = close_reason(pnl_pct)

    attrs = %{exit_price: current_price, pnl: pnl_usd}
    attrs = if close_reason, do: Map.put(attrs, :status, "closed"), else: attrs

    case position |> Position.changeset(attrs) |> Repo.update() do
      {:ok, _} when is_nil(close_reason) ->
        :ok

      {:ok, _} ->
        Logger.info(
          "🔒 Position closed (#{close_reason}): #{position.question} | P&L: $#{Decimal.round(pnl_usd, 2)} (#{pnl_pct |> Decimal.mult(100) |> Decimal.round(1)}%)"
        )

      {:error, changeset} ->
        Logger.error("Failed to update position #{position.id}: #{inspect(changeset.errors)}")
    end
  end

  defp close_reason(pnl_pct) do
    cond do
      Decimal.compare(pnl_pct, @take_profit) != :lt -> "take_profit"
      Decimal.compare(pnl_pct, @stop_loss) != :gt -> "stop_loss"
      true -> nil
    end
  end

  defp calculate_pnl(position, current_price) do
    current_price
    |> Decimal.sub(position.entry_price)
    |> Decimal.div(position.entry_price)
  end

  defp pnl_usd(position, pnl_pct) do
    position.cost |> Decimal.mult(pnl_pct) |> Decimal.round(@money_scale)
  end
end
