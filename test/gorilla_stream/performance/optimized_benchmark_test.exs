defmodule GorillaStream.Performance.OptimizedBenchmarkTest do
  use ExUnit.Case, async: true

  @large_size 100_000

  defp generate_data(size) do
    Enum.map(0..(size - 1), fn i -> {i, :math.sin(i / 10)} end)
  end

  test "compare original and optimized encoder performance" do
    data = generate_data(@large_size)

    # Original encoder
    {orig_time, {:ok, _}} =
      :timer.tc(fn ->
        GorillaStream.Compression.Gorilla.Encoder.encode(data)
      end)

    # Optimized encoder
    {opt_time, {:ok, _}} =
      :timer.tc(fn ->
        GorillaStream.Compression.Gorilla.EncoderOptimized.encode(data)
      end)

    IO.puts("Original encoder time: #{orig_time} µs")
    IO.puts("Optimized encoder time: #{opt_time} µs")
    # Ensure the optimized version is at least 1.5x faster (i.e., time less than 2/3 of original)
    assert opt_time < orig_time * 0.7
  end
end
