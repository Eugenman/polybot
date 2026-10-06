defmodule Polybot.Trading.PositionConstraintsTest do
  @moduledoc """
  The database must reject invalid positions even when application code is bypassed.
  One violation per test: a failed statement aborts the sandbox transaction.
  """
  use Polybot.DataCase, async: true

  import Polybot.Fixtures

  defp raw_insert(market_id, overrides) do
    row =
      Map.merge(
        %{action: "buy_yes", entry_price: "0.5", cost: "100", status: "closed"},
        overrides
      )

    Repo.query(
      """
      INSERT INTO positions (market_id, question, action, entry_price, cost, status, paper, inserted_at, updated_at)
      VALUES ($1, 'q', $2, $3, $4, $5, true, now(), now())
      """,
      [market_id, row.action, Decimal.new(row.entry_price), Decimal.new(row.cost), row.status]
    )
  end

  defp violated_constraint({:error, %Postgrex.Error{postgres: %{constraint: name}}}), do: name

  test "a second open position for the same market" do
    insert_position!(%{market_id: "dup"})

    assert violated_constraint(raw_insert("dup", %{status: "open"})) ==
             "positions_one_open_per_market"
  end

  test "many closed positions for the same market are fine" do
    assert {:ok, _} = raw_insert("m", %{})
    assert {:ok, _} = raw_insert("m", %{})
  end

  test "entry price outside (0, 1)" do
    assert violated_constraint(raw_insert("m", %{entry_price: "1.5"})) ==
             "positions_entry_price_range"
  end

  test "unknown status" do
    assert violated_constraint(raw_insert("m", %{status: "pending"})) == "positions_valid_status"
  end

  test "unknown action" do
    assert violated_constraint(raw_insert("m", %{action: "sell"})) == "positions_valid_action"
  end

  test "non-positive cost" do
    assert violated_constraint(raw_insert("m", %{cost: "0"})) == "positions_cost_positive"
  end
end
