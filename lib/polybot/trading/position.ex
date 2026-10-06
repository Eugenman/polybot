defmodule Polybot.Trading.Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field :market_id, :string
    field :question, :string
    field :action, :string
    field :entry_price, :decimal
    field :shares, :decimal
    field :cost, :decimal
    field :exit_price, :decimal
    field :pnl, :decimal
    field :status, :string, default: "open"
    field :paper, :boolean, default: true

    timestamps()
  end

  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :market_id,
      :question,
      :action,
      :entry_price,
      :shares,
      :cost,
      :exit_price,
      :pnl,
      :status,
      :paper
    ])
    |> validate_required([:market_id, :question, :action, :entry_price])
    |> validate_inclusion(:action, ["buy_yes", "buy_no"])
    |> validate_inclusion(:status, ["open", "closed"])
    |> validate_number(:entry_price, greater_than: 0, less_than: 1)
    |> unique_constraint(:market_id,
      name: :positions_one_open_per_market,
      message: "already has an open position"
    )
    |> check_constraint(:status, name: :positions_valid_status)
    |> check_constraint(:action, name: :positions_valid_action)
    |> check_constraint(:entry_price, name: :positions_entry_price_range)
    |> check_constraint(:cost, name: :positions_cost_positive)
  end
end
