defmodule GorillaStream.Compression.VictoriaMetricsPipelineTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Gorilla

  test "round-trip without VM flag remains lossless" do
    stream = for i <- 0..9, do: {1_700_000_000 + i, :math.sin(i / 10) + 10.0}

    {:ok, bin} = Gorilla.compress(stream, zlib: false, victoria_metrics: false)
    assert is_binary(bin)

    {:ok, back} = Gorilla.decompress(bin)
    assert Enum.count(back) == Enum.count(stream)

    Enum.zip(stream, back)
    |> Enum.each(fn {{ts1, v1}, {ts2, v2}} ->
      assert ts1 == ts2
      assert_in_delta v1, v2, 1.0e-12
    end)
  end

  test "round-trip with VM flag and counter delta encoding remains lossless" do
    # Build a monotonic counter with decimals
    values = [100.01, 110.02, 125.02, 125.02, 140.37]
    stream = Enum.with_index(values, fn v, idx -> {1_700_000_000 + idx, v} end)

    {:ok, bin} = Gorilla.compress(stream, victoria_metrics: true, is_counter: true, scale_decimals: :auto, zlib: false)
    {:ok, back} = Gorilla.decompress(bin)

    Enum.zip(stream, back)
    |> Enum.each(fn {{ts1, v1}, {ts2, v2}} ->
      assert ts1 == ts2
      assert_in_delta v1, v2, 1.0e-9
    end)
  end
end

