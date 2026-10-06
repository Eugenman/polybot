defmodule Polybot.Scheduler do
  @moduledoc """
  GenServer that scans Polymarket every 30 minutes,
  analyzes markets with Claude and logs decisions.
  """
  use GenServer
  require Logger

  # 30 minutes
  @interval_ms 30 * 60 * 1000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def run_now do
    GenServer.cast(__MODULE__, :scan)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("Scheduler started, first scan in 10 seconds")
    Process.send_after(self(), :scan, 10_000)
    {:ok, %{cycle: 0, decisions: []}}
  end

  @impl true
  def handle_info(:scan, state) do
    cycle = state.cycle + 1
    Logger.info("Starting market scan cycle #{cycle}")

    decisions = scan_markets(cycle)
    Polybot.Trading.PositionManager.update_positions()

    # Schedule next scan
    Process.send_after(self(), :scan, @interval_ms)

    {:noreply, %{state | cycle: cycle, decisions: decisions}}
  end

  @impl true
  def handle_cast(:scan, state) do
    Logger.info("Manual scan triggered")
    # A manual scan is attributed to the current cycle and does not start a new one.
    decisions = scan_markets(state.cycle)
    Polybot.Trading.PositionManager.update_positions()
    {:noreply, %{state | decisions: decisions}}
  end

  # Private

  defp scan_markets(cycle) do
    case Polybot.Polymarket.Gamma.fetch_political_and_sports_markets() do
      {:ok, markets} ->
        Logger.info("Fetched #{length(markets)} relevant markets")
        analyze_markets(markets, cycle)

      {:error, reason} ->
        Logger.error("Failed to fetch markets: #{inspect(reason)}")
        []
    end
  end

  # A fatal API error (bad key, no credits) stops the scan: every remaining market would fail
  # the same way. The next scheduled scan tries again, so the bot recovers on its own once
  # the problem is fixed.
  defp analyze_markets(markets, cycle) do
    markets
    |> Enum.take(20)
    |> Enum.reduce_while([], fn market, decisions ->
      # Spreads Claude requests out to stay under API rate limits.
      Process.sleep(request_delay_ms())

      case analyze_market(market, cycle) do
        {:ok, decision} ->
          {:cont, [decision | decisions]}

        :skip ->
          {:cont, decisions}

        {:halt, reason} ->
          Logger.error("Stopping scan cycle #{cycle}, Claude API is unusable: #{reason}")
          {:halt, decisions}
      end
    end)
    |> Enum.reverse()
  end

  # One bad market must not crash the scheduler: a crash would restart it, the first scan
  # would run again after 10 s, and a persistent error would turn into a tight retry loop
  # against the Claude and Gamma APIs.
  defp analyze_market(market, cycle) do
    case Polybot.AI.Analyst.analyze(market) do
      {:ok, decision} ->
        log_decision(decision)
        Polybot.Trading.PaperTrader.process_decision(decision, cycle)
        {:ok, decision}

      {:error, {:fatal, reason}} ->
        {:halt, reason}

      {:error, reason} ->
        Logger.error("Failed to analyze #{market.question}: #{inspect(reason)}")
        :skip
    end
  rescue
    error ->
      Logger.error(
        "Crashed while processing #{market.id}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :skip
  end

  defp request_delay_ms do
    Application.get_env(:polybot, __MODULE__, [])[:request_delay_ms] || 2000
  end

  defp log_decision(decision) do
    Logger.info("""
    📊 Decision:
       Market: #{decision.question}
       Market price: #{decision.market_price}
       Our probability: #{decision.our_probability}
       Edge: #{decision.edge}
       Action: #{decision.action}
       Confidence: #{decision.confidence}
    """)
  end
end
