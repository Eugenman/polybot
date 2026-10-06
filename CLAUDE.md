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
Claude estimates the probability of a market outcome; the bot compares it with the market price
and opens a paper position if the edge is large enough.

## Current rules (as implemented)
- Capital: $1000 (constant), position size: 10% of capital
- Min edge to enter: 10%
- Take-profit: +50%, stop-loss: -40% per position
- One open position per market
- Max open positions / total exposure: not enforced yet

## Database tables
- `decisions` — every analysis result
- `positions` — paper positions with P&L
- `markets` — created by migration, currently unused

## Environment
- Paper trading only, no real orders are placed
- Run `mix precommit` before finishing changes (see AGENTS.md)
