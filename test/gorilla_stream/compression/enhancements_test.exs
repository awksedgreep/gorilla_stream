defmodule GorillaStream.Compression.EnhancementsTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Enhancements

  test "scale_floats_to_ints with :auto chooses sensible N and round-trips" do
    values = [1.23, 4.56, 7.89]
    {ints, n} = Enhancements.scale_floats_to_ints(values, :auto)

    assert is_list(ints)
    assert is_integer(n)
    assert n >= 2

    scale = :math.pow(10, n)
    back = Enum.map(ints, &(&1 / scale))

    Enum.zip(values, back)
    |> Enum.each(fn {orig, got} ->
      assert_in_delta orig, got, 1.0e-9
    end)
  end

  test "delta_encode_counter and delta_decode_counter are inverses" do
    values = [100, 110, 125, 130]
    deltas = Enhancements.delta_encode_counter(values)
    assert deltas == [100, 10, 15, 5]

    decoded = Enhancements.delta_decode_counter(deltas)
    assert decoded == values
  end

  test "monotonic_non_decreasing? detects monotonicity" do
    assert Enhancements.monotonic_non_decreasing?([1, 1, 2, 3])
    refute Enhancements.monotonic_non_decreasing?([1, 2, 1])
  end
end

