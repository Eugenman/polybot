defmodule Polybot.AI.AnalystTest do
  use ExUnit.Case, async: true

  import Polybot.Fixtures
  alias Polybot.AI.Analyst

  # Answers Claude requests in order and reports each request body to the test process.
  defp stub_claude(responses) do
    test_pid = self()
    {:ok, queue} = Agent.start_link(fn -> responses end)

    Req.Test.stub(Analyst, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:claude_request, Jason.decode!(body)})

      case Agent.get_and_update(queue, fn [next | rest] -> {next, rest} end) do
        {status, response} -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(response)
        response -> Req.Test.json(conn, response)
      end
    end)
  end

  defp quick(fields),
    do: claude_json(Map.merge(%{"confidence" => "high", "reasoning" => "r"}, fields))

  describe "edge" do
    test "is computed from the probability, not taken from the model" do
      stub_claude([quick(%{"probability" => 0.45, "edge" => 0.9, "action" => "buy_yes"})])

      assert {:ok, decision} = Analyst.analyze(market("0.40", "0.60"))
      assert Decimal.equal?(decision.edge, "0.05")
      assert Decimal.equal?(decision.our_probability, "0.45")
    end

    test "a small edge needs only the quick analysis" do
      stub_claude([quick(%{"probability" => 0.45, "action" => "buy_yes"})])

      assert {:ok, _} = Analyst.analyze(market("0.40", "0.60"))
      assert_received {:claude_request, request}
      refute Map.has_key?(request, "tools")
      refute_received {:claude_request, _}
    end

    test "an edge of 10% or more triggers a deep analysis with web search" do
      stub_claude([
        quick(%{"probability" => 0.60, "action" => "buy_yes"}),
        quick(%{"probability" => 0.65, "action" => "buy_yes", "reasoning" => "deep"})
      ])

      assert {:ok, decision} = Analyst.analyze(market("0.40", "0.60"))
      assert decision.reasoning == "deep"
      assert Decimal.equal?(decision.edge, "0.25")

      assert_received {:claude_request, quick_request}
      assert_received {:claude_request, deep_request}
      refute Map.has_key?(quick_request, "tools")
      assert [%{"name" => "web_search"}] = deep_request["tools"]
    end
  end

  describe "action" do
    test "passes the NO price through for buy_no decisions" do
      stub_claude([
        quick(%{"probability" => 0.20, "action" => "buy_no"}),
        quick(%{"probability" => 0.20, "action" => "buy_no"})
      ])

      assert {:ok, decision} = Analyst.analyze(market("0.40", "0.60"))
      assert decision.action == "buy_no"
      assert decision.no_price == Decimal.new("0.60")
    end

    test "an action contradicting the edge becomes pass" do
      # probability 0.70 > price 0.40 means YES is underpriced, so buying NO makes no sense
      stub_claude([
        quick(%{"probability" => 0.70, "action" => "buy_no"}),
        quick(%{"probability" => 0.70, "action" => "buy_no"})
      ])

      assert {:ok, %{action: "pass"}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "sell_yes is normalized to buy_no" do
      stub_claude([quick(%{"probability" => 0.35, "action" => "sell_yes"})])

      assert {:ok, %{action: "buy_no"}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "unknown actions become pass" do
      stub_claude([quick(%{"probability" => 0.45, "action" => "yolo"})])

      assert {:ok, %{action: "pass"}} = Analyst.analyze(market("0.40", "0.60"))
    end
  end

  describe "response parsing" do
    test "extracts JSON wrapped in markdown and prose" do
      text = """
      Here is my analysis:
      ```json
      {"probability": 0.45, "confidence": "low", "reasoning": "r", "action": "pass"}
      ```
      """

      stub_claude([claude_response(text)])

      assert {:ok, %{confidence: "low"}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "strips citation tags from reasoning" do
      stub_claude([
        quick(%{
          "probability" => 0.45,
          "action" => "pass",
          "reasoning" => ~s(<cite index="1">News</cite> says so)
        })
      ])

      assert {:ok, %{reasoning: "News says so"}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "rejects a probability outside [0, 1]" do
      stub_claude([quick(%{"probability" => 1.5, "action" => "buy_yes"})])

      assert {:error, "Claude returned no valid probability" <> _} =
               Analyst.analyze(market("0.40", "0.60"))
    end

    test "rejects a missing probability" do
      stub_claude([quick(%{"action" => "buy_yes"})])

      assert {:error, "Claude returned no valid probability" <> _} =
               Analyst.analyze(market("0.40", "0.60"))
    end

    test "returns an error for a non-JSON answer" do
      stub_claude([claude_response("Sorry, I can't help with that.")])

      assert {:error, "Failed to parse Claude response" <> _} =
               Analyst.analyze(market("0.40", "0.60"))
    end

    test "returns an error for an API error status" do
      stub_claude([{529, %{"error" => %{"type" => "overloaded_error"}}}])

      assert {:error, "API error 529" <> _} = Analyst.analyze(market("0.40", "0.60"))
    end
  end

  describe "API errors" do
    # Response body from a real run with an empty credit balance.
    @no_credits %{
      "type" => "error",
      "error" => %{
        "type" => "invalid_request_error",
        "message" =>
          "Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."
      }
    }

    test "an empty credit balance is fatal" do
      stub_claude([{400, @no_credits}])

      assert {:error, {:fatal, "API error 400" <> _}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "an invalid API key is fatal" do
      stub_claude([{401, %{"error" => %{"type" => "authentication_error"}}}])

      assert {:error, {:fatal, "API error 401" <> _}} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "other bad requests only fail this market" do
      stub_claude([{400, %{"error" => %{"message" => "prompt is too long"}}}])

      assert {:error, "API error 400" <> _} = Analyst.analyze(market("0.40", "0.60"))
    end

    test "rate limits are transient" do
      stub_claude([{429, %{"error" => %{"type" => "rate_limit_error"}}}])

      assert {:error, "API error 429" <> _} = Analyst.analyze(market("0.40", "0.60"))
    end
  end

  test "does not call Claude for a market without tradable prices" do
    stub_claude([])

    assert {:error, "Market m1 has no tradable prices"} = Analyst.analyze(market(nil, "0.60"))
    refute_received {:claude_request, _}
  end
end
