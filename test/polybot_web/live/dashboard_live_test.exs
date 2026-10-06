defmodule PolybotWeb.DashboardLiveTest do
  use PolybotWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Polybot.Fixtures

  test "shows open positions with P&L, colored by sign", %{conn: conn} do
    insert_position!(%{market_id: "win", question: "Winning market", pnl: Decimal.new("12.345")})
    insert_position!(%{market_id: "loss", question: "Losing market", pnl: Decimal.new("-7.5")})
    insert_position!(%{market_id: "old", question: "Closed market", status: "closed"})

    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Winning market"
    refute html =~ "Closed market"
    # Two open positions of $100 each
    assert view |> element("div.text-3xl", "$200") |> has_element?()
    assert view |> element("td.text-success", "$12.35") |> has_element?()
    # Decimals are structs: a `pnl >= 0` check would wrongly render this loss as green
    assert view |> element("td.text-error", "$-7.50") |> has_element?()
  end

  test "renders an empty dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Polybot Dashboard"
    assert html =~ "$0"
  end
end
