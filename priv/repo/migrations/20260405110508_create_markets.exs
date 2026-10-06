defmodule Polybot.Repo.Migrations.CreateMarkets do
  use Ecto.Migration

  def change do
    create table(:markets) do
      add :market_id, :string, null: false
      add :question, :string, null: false
      add :yes_price, :float
      add :no_price, :float
      add :volume, :float
      add :liquidity, :float
      add :end_date, :string
      add :condition_id, :string

      timestamps()
    end

    create unique_index(:markets, [:market_id])
  end
end
