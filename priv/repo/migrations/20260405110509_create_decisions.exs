defmodule Polybot.Repo.Migrations.CreateDecisions do
  use Ecto.Migration

  def change do
    create table(:decisions) do
      add :market_id, :string, null: false
      add :question, :string, null: false
      add :market_price, :float
      add :our_probability, :float
      add :confidence, :string
      add :edge, :float
      add :action, :string
      add :reasoning, :text
      add :cycle, :integer, default: 0

      timestamps()
    end

    create index(:decisions, [:market_id])
    create index(:decisions, [:action])
  end
end