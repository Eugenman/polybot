defmodule Polybot.Trading.Decision do
  use Ecto.Schema
  import Ecto.Changeset

  schema "decisions" do
    field :market_id, :string
    field :question, :string
    field :market_price, :float
    field :our_probability, :float
    field :confidence, :string
    field :edge, :float
    field :action, :string
    field :reasoning, :string
    field :cycle, :integer, default: 0

    timestamps()
  end

  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [:market_id, :question, :market_price, :our_probability,
                    :confidence, :edge, :action, :reasoning, :cycle])
    |> validate_required([:market_id, :question, :action])
  end
end