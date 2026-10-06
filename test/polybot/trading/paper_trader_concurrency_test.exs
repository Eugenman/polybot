defmodule Polybot.Trading.PaperTraderConcurrencyTest do
  @moduledoc """
  Risk limits under real concurrency.

  Inside the SQL sandbox all processes share one connection, so a race can't happen there.
  These tests switch the sandbox to :auto mode: every task gets its own connection and its
  own transaction, like separate requests in production. Data is real, so it's cleaned up.
  """
  use ExUnit.Case, async: false

  import Polybot.Fixtures
  alias Ecto.Adapters.SQL.Sandbox
  alias Polybot.Repo
  alias Polybot.Trading.{PaperTrader, Position}

  @moduletag :capture_log

  setup do
    Sandbox.mode(Repo, :auto)
    Repo.delete_all(Position)

    on_exit(fn ->
      Repo.delete_all(Position)
      Sandbox.mode(Repo, :manual)
    end)
  end

  defp open_concurrently(market_ids) do
    market_ids
    |> Task.async_stream(&PaperTrader.open_position(decision(%{market_id: &1})),
      max_concurrency: length(market_ids)
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.frequencies_by(fn
      {:ok, _} -> :ok
      {:error, reason} -> reason
    end)
  end

  test "20 concurrent opens on different markets open exactly 5 positions" do
    results = open_concurrently(Enum.map(1..20, &"m#{&1}"))

    assert results == %{ok: 5, max_open_positions: 15}
    assert Repo.aggregate(Position, :count) == 5
  end

  test "10 concurrent opens on the same market open exactly 1 position" do
    results = open_concurrently(List.duplicate("same", 10))

    assert results == %{ok: 1, already_open: 9}
    assert Repo.aggregate(Position, :count) == 1
  end
end
