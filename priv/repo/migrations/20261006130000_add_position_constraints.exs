defmodule Polybot.Repo.Migrations.AddPositionConstraints do
  use Ecto.Migration

  # Invariants enforced by the database, not only by application code:
  # at most one open position per market, and no positions with impossible values.
  def up do
    check_no_duplicate_open_positions!()

    create unique_index(:positions, [:market_id],
             where: "status = 'open'",
             name: :positions_one_open_per_market
           )

    create constraint(:positions, :positions_valid_status, check: "status IN ('open', 'closed')")

    create constraint(:positions, :positions_valid_action,
             check: "action IN ('buy_yes', 'buy_no')"
           )

    create constraint(:positions, :positions_entry_price_range,
             check: "entry_price > 0 AND entry_price < 1"
           )

    create constraint(:positions, :positions_cost_positive, check: "cost > 0")
  end

  def down do
    drop constraint(:positions, :positions_cost_positive)
    drop constraint(:positions, :positions_entry_price_range)
    drop constraint(:positions, :positions_valid_action)
    drop constraint(:positions, :positions_valid_status)
    drop index(:positions, [:market_id], name: :positions_one_open_per_market)
  end

  defp check_no_duplicate_open_positions! do
    %{rows: duplicates} =
      repo().query!("""
      SELECT market_id, count(*) FROM positions
      WHERE status = 'open'
      GROUP BY market_id
      HAVING count(*) > 1
      """)

    if duplicates != [] do
      raise """
      Cannot add unique index: markets with more than one open position: #{inspect(duplicates)}.
      Close or delete the duplicates first, then rerun the migration.
      """
    end
  end
end
