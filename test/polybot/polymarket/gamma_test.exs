defmodule Polybot.Polymarket.GammaTest do
  use ExUnit.Case, async: true

  import Polybot.Fixtures
  alias Polybot.Polymarket.Gamma

  defp stub_markets(markets) do
    Req.Test.stub(Gamma, fn conn -> Req.Test.json(conn, markets) end)
  end

  describe "fetch_political_and_sports_markets/1" do
    test "parses prices as Decimal" do
      stub_markets([gamma_market("1", "Will the election go to a runoff?", ["0.535", "0.465"])])

      assert {:ok, [market]} = Gamma.fetch_political_and_sports_markets()
      assert market.yes_price == Decimal.new("0.535")
      assert market.no_price == Decimal.new("0.465")
    end

    test "keeps only relevant, liquid, open markets with tradable prices" do
      stub_markets([
        gamma_market("ok", "Will the senate pass the bill?", ["0.4", "0.6"]),
        gamma_market("irrelevant", "Will it rain in Paris?", ["0.4", "0.6"]),
        gamma_market("low_volume", "Will the senate vote?", ["0.4", "0.6"], %{"volume" => "10"}),
        gamma_market("closed", "Will the senate vote?", ["0.4", "0.6"], %{"closed" => true}),
        gamma_market("no_prices", "Will the war end?", nil),
        gamma_market("resolved", "Will the fed cut?", ["1", "0"]),
        gamma_market("garbage", "Will the fed cut?", ["n/a", "0.5"])
      ])

      assert {:ok, markets} = Gamma.fetch_political_and_sports_markets()
      assert Enum.map(markets, & &1.id) == ["ok"]
    end

    test "returns an error on a non-200 response" do
      Req.Test.stub(Gamma, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)

      assert {:error, "Unexpected status: 503"} = Gamma.fetch_political_and_sports_markets()
    end
  end

  describe "fetch_market/1" do
    test "fetches a single market by id" do
      Req.Test.stub(Gamma, fn conn ->
        assert conn.request_path == "/markets/42"
        Req.Test.json(conn, gamma_market("42", "q", ["0.3", "0.7"]))
      end)

      assert {:ok, %{id: "42", no_price: no_price}} = Gamma.fetch_market("42")
      assert no_price == Decimal.new("0.7")
    end
  end

  describe "tradable?/1" do
    test "requires both prices strictly between 0 and 1" do
      assert Gamma.tradable?(market("0.4", "0.6"))
      refute Gamma.tradable?(market("0", "1"))
      refute Gamma.tradable?(market("1", "0"))
      refute Gamma.tradable?(market(nil, "0.6"))
      refute Gamma.tradable?(market("0.4", nil))
    end
  end
end
