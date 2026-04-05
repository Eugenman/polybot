# Polybot — Polymarket AI Trading Bot

## Stack
- Elixir / Phoenix 1.8.5
- PostgreSQL
- Claude API (Decision Engine)
- Polymarket CLOB + Gamma API

## Architecture
- `Polybot.Gamma` — fetches markets from Polymarket Gamma API
- `Polybot.CLOB` — order book, prices, order execution
- `Polybot.AI.Analyst` — Claude-powered decision engine (GenServer)
- `Polybot.RiskManager` — position sizing, max exposure, stop-loss
- `Polybot.Scheduler` — scans markets every 30 min (GenServer)
- `Polybot.Executor` — paper/live trade execution

## Strategy
AI forecasting: Claude analyzes market, estimates probability,
compares with current price, trades if edge >= 15%

## Rules
- Max position: 10% of capital
- Max open positions: 5
- Min edge to enter: 15%
- Stop-loss: -40% per position

## Database tables
- markets
- decisions
- positions
- trades

## Environment
- WSL2 Ubuntu on Windows
- Paper trading by default, live behind feature flag