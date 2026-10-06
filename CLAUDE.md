# Polybot — Polymarket AI Paper-Trading Bot

## Stack
- Elixir / Phoenix 1.8.5, LiveView
- PostgreSQL (Ecto)
- Claude API (decision engine, `claude-haiku-4-5` with web search)
- Polymarket Gamma API (market data, read-only)

## Architecture
- `Polybot.Scheduler` — GenServer, scans markets every 30 min (first scan 10 s after start)
- `Polybot.Polymarket.Gamma` — fetches and filters markets (political/sports keywords, min volume)
- `Polybot.AI.Analyst` — two-stage analysis: quick estimate, then deep analysis with web search if edge looks promising
- `Polybot.Trading.PaperTrader` — stores decisions, opens paper positions
- `Polybot.Trading.PositionManager` — refreshes prices, updates P&L, closes on take-profit / stop-loss
- `PolybotWeb.DashboardLive` — `/dashboard`, open positions and recent decisions

## Strategy
Claude estimates only the probability that a market resolves YES. The bot computes
`edge = probability - yes_price` itself and opens a paper position if the edge is large enough.

## Current rules (as implemented)
- Capital: $1000 (constant), position size: 10% of capital
- Min edge to enter: 10%
- `buy_yes` requires edge > 0, `buy_no` requires edge < 0; a contradicting model action becomes `pass`
- YES positions are bought and tracked at the YES price, NO positions at the NO price
- Only markets with both prices strictly between 0 and 1 are analyzed
- Take-profit: +50%, stop-loss: -40% per position (P&L update and close in one UPDATE)
- One open position per market (partial unique index `positions_one_open_per_market`)
- Max 5 open positions, max exposure 50% of capital
- Limit checks and insert run in one transaction under `pg_advisory_xact_lock`, so concurrent
  opens can't exceed the limits

## Database invariants
`positions` has CHECK constraints for `status`, `action`, `0 < entry_price < 1` and `cost > 0`.
Keep changeset validations and DB constraints in sync; new invariants go into a migration too.

## Database tables
- `decisions` — every analysis result
- `positions` — paper positions with P&L
- `markets` — created by migration, currently unused

## Conventions
- Prices, probabilities, money and shares are `Decimal` (DB: `numeric`). Never use floats for them.
- Parse external numbers with `Polybot.Decimals.to_decimal/1`.
- Compare Decimals with `Decimal.compare/2` / `Decimal.negative?/1`, never with `>=` / `<` (structs compare as terms).

## Environment
- Paper trading only, no real orders are placed
- Run `mix precommit` before finishing changes (see AGENTS.md)
