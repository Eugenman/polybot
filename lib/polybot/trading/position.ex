defmodule Polybot.Trading.Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field :market_id, :string
    field :question, :string
    field :action, :string
    field :entry_price, :float
    field :shares, :float
    field :cost, :float
    field :exit_price, :float
    field :pnl, :float
    field :status, :string, default: "open"
    field :paper, :boolean, default: true

    timestamps()
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:market_id, :question, :action, :entry_price,
                    :shares, :cost, :exit_price, :pnl, :status, :paper])
    |> validate_required([:market_id, :question, :action, :entry_price])
  end
end