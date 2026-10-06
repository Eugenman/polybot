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
  @take_profit 0.5
  # close if loss <= -40%
  @stop_loss -0.4

  def update_positions do
    positions =
      Repo.all(
        from p in Position,
          where: p.status == "open" and p.paper == true
      )

    Logger.info("Updating #{length(positions)} open positions")

    Enum.each(positions, fn position ->
      case Gamma.fetch_market(position.market_id) do
        {:ok, market} ->
          current_price = get_current_price(market, position.action)
          pnl_pct = calculate_pnl(position, current_price)
          update_position_pnl(position, current_price, pnl_pct)
          maybe_close_position(position, current_price, pnl_pct)

        {:error, reason} ->
          Logger.error("Failed to fetch market #{position.market_id}: #{inspect(reason)}")
      end
    end)
  end

  defp get_current_price(market, "buy_yes"), do: market.yes_price
  defp get_current_price(market, "buy_no"), do: market.no_price
  defp get_current_price(market, _), do: market.yes_price

  defp calculate_pnl(position, current_price) do
    (current_price - position.entry_price) / position.entry_price
  end

  defp update_position_pnl(position, current_price, pnl_pct) do
    pnl_usd = position.cost * pnl_pct

    position
    |> Position.changeset(%{
      exit_price: current_price,
      pnl: pnl_usd
    })
    |> Repo.update()
  end

  defp maybe_close_position(position, current_price, pnl_pct) do
    cond do
      pnl_pct >= @take_profit ->
        close_position(position, current_price, pnl_pct, "take_profit")

      pnl_pct <= @stop_loss ->
        close_position(position, current_price, pnl_pct, "stop_loss")

      true ->
        :ok
    end
  end

  defp close_position(position, current_price, pnl_pct, reason) do
    pnl_usd = position.cost * pnl_pct

    position
    |> Position.changeset(%{
      status: "closed",
      exit_price: current_price,
      pnl: pnl_usd
    })
    |> Repo.update()

    Logger.info(
      "🔒 Position closed (#{reason}): #{position.question} | P&L: $#{Float.round(pnl_usd, 2)} (#{Float.round(pnl_pct * 100, 1)}%)"
    )
  end
end
