defmodule Polybot.SchedulerTest do
  # Not async: the cycle opens positions (advisory lock, see PaperTraderTest).
  use Polybot.DataCase, async: false

  @moduletag :capture_log

  import Polybot.Fixtures
  alias Polybot.AI.Analyst
  alias Polybot.Polymarket.Gamma
  alias Polybot.Scheduler
  alias Polybot.Trading.{Decision, Position}

  @markets [
    gamma_market("runoff", "Will the election go to a runoff?", ["0.70", "0.30"]),
    gamma_market("crash", "Will the senate pass the bill?", ["0.40", "0.60"]),
    gamma_market("no_prices", "Will the war end?", nil)
  ]

  setup do
    Req.Test.stub(Gamma, fn
      %{request_path: "/markets"} = conn ->
        Req.Test.json(conn, @markets)

      %{request_path: "/markets/" <> id} = conn ->
        Req.Test.json(conn, Enum.find(@markets, &(&1["id"] == id)))
    end)

    Req.Test.stub(Analyst, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      cond do
        body =~ "runoff" ->
          Req.Test.json(
            conn,
            claude_json(%{
              "probability" => 0.4,
              "confidence" => "high",
              "reasoning" => "r",
              "action" => "buy_no"
            })
          )

        body =~ "senate" ->
          raise "unexpected failure while analyzing"
      end
    end)

    :ok
  end

  test "a scan cycle stores decisions, opens positions and survives a failing market" do
    assert {:noreply, %{cycle: 1}} = Scheduler.handle_info(:scan, %{cycle: 0, decisions: []})

    # The crashing market didn't stop the cycle, the market without prices was skipped.
    assert [%Decision{market_id: "runoff", cycle: 1, action: "buy_no"}] = Repo.all(Decision)

    assert [%Position{market_id: "runoff", action: "buy_no", entry_price: entry}] =
             Repo.all(Position)

    assert Decimal.equal?(entry, "0.30")
  end

  test "a manual scan keeps the current cycle number" do
    assert {:noreply, %{cycle: 3}} = Scheduler.handle_cast(:scan, %{cycle: 3, decisions: []})
    assert [%Decision{cycle: 3}] = Repo.all(Decision)
  end
end
