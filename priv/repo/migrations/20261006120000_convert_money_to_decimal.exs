defmodule Polybot.Repo.Migrations.ConvertMoneyToDecimal do
  use Ecto.Migration

  # Prices and probabilities are in [0, 1]; money and shares need more integer digits.
  # Existing float values are rounded to the column scale by Postgres.
  @price [precision: 10, scale: 6]
  @amount [precision: 20, scale: 8]

  @columns %{
    positions: [
      entry_price: @price,
      exit_price: @price,
      shares: @amount,
      cost: @amount,
      pnl: @amount
    ],
    decisions: [
      market_price: @price,
      our_probability: @price,
      edge: @price
    ]
  }

  # Explicit up/down: `modify ..., from: :float` would reuse precision/scale on rollback
  # and generate invalid SQL (`float(10,6)`).
  def up do
    for {table, columns} <- @columns do
      alter table(table) do
        for {column, opts} <- columns, do: modify(column, :decimal, opts)
      end
    end
  end

  def down do
    for {table, columns} <- @columns do
      alter table(table) do
        for {column, _opts} <- columns, do: modify(column, :float)
      end
    end
  end
end
