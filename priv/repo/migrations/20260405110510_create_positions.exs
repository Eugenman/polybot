defmodule Polybot.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add :market_id, :string, null: false
      add :question, :string, null: false
      add :action, :string, null: false
      add :entry_price, :float
      add :shares, :float
      add :cost, :float
      add :exit_price, :float
      add :pnl, :float
      add :status, :string, default: "open"
      add :paper, :boolean, default: true

      timestamps()
    end

    create index(:positions, [:market_id])
    create index(:positions, [:status])
  end
end
