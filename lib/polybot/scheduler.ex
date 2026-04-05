defmodule Polybot.Scheduler do
  @moduledoc """
  GenServer that scans Polymarket every 30 minutes,
  analyzes markets with Claude and logs decisions.
  """
  use GenServer
  require Logger

  @interval_ms 30 * 60 * 1000  # 30 minutes

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
    Logger.info("Starting market scan cycle #{state.cycle + 1}")

    decisions = scan_markets()

    # Schedule next scan
    Process.send_after(self(), :scan, @interval_ms)

    {:noreply, %{state | cycle: state.cycle + 1, decisions: decisions}}
  end

  @impl true
  def handle_cast(:scan, state) do
    Logger.info("Manual scan triggered")
    decisions = scan_markets()
    {:noreply, %{state | decisions: decisions}}
  end

  # Private

  defp scan_markets do
    case Polybot.Polymarket.Gamma.fetch_markets() do
      {:ok, markets} ->
        Logger.info("Fetched #{length(markets)} markets")
        analyze_markets(markets)

      {:error, reason} ->
        Logger.error("Failed to fetch markets: #{inspect(reason)}")
        []
    end
  end

  defp analyze_markets(markets) do
    markets
    |> Enum.take(10)
    |> Enum.map(fn market ->
      case Polybot.AI.Analyst.analyze(market) do
        {:ok, decision} ->
          log_decision(decision)
          Polybot.Trading.PaperTrader.process_decision(decision, 0)
          decision

        {:error, reason} ->
          Logger.error("Failed to analyze #{market.question}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
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