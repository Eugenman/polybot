defmodule Polybot.DecimalsTest do
  use ExUnit.Case, async: true

  import Polybot.Decimals, only: [to_decimal: 1]

  test "parses API price strings without going through floats" do
    assert to_decimal("0.535") == Decimal.new("0.535")
    assert to_decimal(" 0.1 ") == Decimal.new("0.1")
  end

  test "converts JSON floats to their shortest decimal representation" do
    assert to_decimal(0.65) == Decimal.new("0.65")
    assert to_decimal(0.1) == Decimal.new("0.1")
  end

  test "converts integers" do
    assert to_decimal(1) == Decimal.new(1)
  end

  test "returns nil for missing, malformed and non-finite values" do
    assert to_decimal(nil) == nil
    assert to_decimal("") == nil
    assert to_decimal("abc") == nil
    assert to_decimal("0.5abc") == nil
    assert to_decimal("NaN") == nil
    assert to_decimal("Infinity") == nil
    assert to_decimal(%{}) == nil
  end
end
