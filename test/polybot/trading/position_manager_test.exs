defmodule Polybot.Trading.PositionManagerTest do
  use Polybot.DataCase, async: true

  @moduletag :capture_log

  import Polybot.Fixtures
  alias Polybot.Polymarket.Gamma
  alias Polybot.Trading.PositionManager

  # Gamma answers every /markets/:id request with these YES/NO prices.
  defp stub_prices(prices) do
    Req.Test.stub(Gamma, fn conn ->
      "/markets/" <> id = conn.request_path
      Req.Test.json(conn, gamma_market(id, "q", prices))
    end)
  end

  test "updates P&L and keeps the position open between the thresholds" do
    position = insert_position!(%{entry_price: Decimal.new("0.40")})
    stub_prices(["0.50", "0.50"])

    PositionManager.update_positions()

    position = Repo.reload!(position)
    assert position.status == "open"
    assert Decimal.equal?(position.exit_price, "0.50")
    assert Decimal.equal?(position.pnl, "25")
  end

  test "take profit closes the position at exactly +50%" do
    position = insert_position!(%{entry_price: Decimal.new("0.40")})
    stub_prices(["0.60", "0.40"])

    PositionManager.update_positions()

    position = Repo.reload!(position)
    assert position.status == "closed"
    assert Decimal.equal?(position.pnl, "50")
  end

  test "stop loss closes the position at -40%" do
    position = insert_position!(%{entry_price: Decimal.new("0.50")})
    stub_prices(["0.30", "0.70"])

    PositionManager.update_positions()

    position = Repo.reload!(position)
    assert position.status == "closed"
    assert Decimal.equal?(position.pnl, "-40")
  end

  test "a NO position is tracked against the NO price" do
    position = insert_position!(%{action: "buy_no", entry_price: Decimal.new("0.60")})
    # YES fell, so NO rose from 0.60 to 0.75: +25%
    stub_prices(["0.25", "0.75"])

    PositionManager.update_positions()

    assert Decimal.equal?(Repo.reload!(position).pnl, "25")
  end

  test "a market resolved against us is a full loss" do
    position = insert_position!(%{entry_price: Decimal.new("0.40")})
    stub_prices(["0", "1"])

    PositionManager.update_positions()

    position = Repo.reload!(position)
    assert position.status == "closed"
    assert Decimal.equal?(position.pnl, "-100")
  end

  test "leaves the position untouched when the market has no price" do
    position = insert_position!()
    stub_prices(nil)

    PositionManager.update_positions()

    assert %{status: "open", pnl: nil} = Repo.reload!(position)
  end

  test "leaves the position untouched when Gamma fails" do
    position = insert_position!()
    Req.Test.stub(Gamma, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    PositionManager.update_positions()

    assert %{status: "open", pnl: nil} = Repo.reload!(position)
  end

  test "ignores closed positions" do
    position = insert_position!(%{status: "closed"})
    Req.Test.stub(Gamma, fn _conn -> flunk("closed positions must not be refreshed") end)

    PositionManager.update_positions()

    assert %{status: "closed", pnl: nil} = Repo.reload!(position)
  end
end
