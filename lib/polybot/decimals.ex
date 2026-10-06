defmodule Polybot.Decimals do
  @moduledoc """
  Converts external numeric values (API strings, JSON numbers) to `Decimal`.
  Prices and money are never calculated with floats.
  """

  @doc """
  Returns a `Decimal`, or `nil` if the value is missing or not a finite number.
  """
  def to_decimal(nil), do: nil
  def to_decimal(%Decimal{} = value), do: finite(value)
  def to_decimal(value) when is_integer(value), do: Decimal.new(value)

  # JSON numbers (e.g. from the LLM) arrive as floats; from_float keeps the shortest
  # representation, so 0.65 becomes Decimal "0.65", not 0.65000000000000002220...
  def to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  def to_decimal(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} -> finite(decimal)
      _ -> nil
    end
  end

  def to_decimal(_), do: nil

  defp finite(decimal) do
    if Decimal.nan?(decimal) or Decimal.inf?(decimal), do: nil, else: decimal
  end
end
