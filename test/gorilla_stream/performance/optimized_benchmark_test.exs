defmodule GorillaStream.Performance.OptimizedBenchmarkTest do
  # Performance-sensitive; run synchronously to avoid scheduler contention
  use ExUnit.Case, async: false

  @large_size 100_000

  defp generate_data(size) do
    # Use realistic temperature profile with deterministic seed
    GorillaStream.Performance.RealisticData.generate(size, :temperature,
      interval: 60,
      seed: {1, 2, 3}
    )
  end

  test "compare original and optimized encoder performance" do
    data = generate_data(@large_size)

    # Warmup both implementations to stabilize measurements (JIT, cache, GC)
    _ = GorillaStream.Compression.Gorilla.Encoder.encode(data)
    _ = GorillaStream.Compression.Gorilla.EncoderOptimized.encode(data)

    measure = fn fun ->
      # Run multiple times and take the median to reduce noise
      times =
        for _ <- 1..5 do
          {t, {:ok, _}} = :timer.tc(fun)
          t
        end

      times |> Enum.sort() |> Enum.at(2)
    end

    orig_time = measure.(fn -> GorillaStream.Compression.Gorilla.Encoder.encode(data) end)
    opt_time = measure.(fn -> GorillaStream.Compression.Gorilla.EncoderOptimized.encode(data) end)

    IO.puts("Original encoder time (median of 5): #{orig_time} µs")
    IO.puts("Optimized encoder time (median of 5): #{opt_time} µs")

    # The original encoder has been optimized recently, narrowing the gap.
    # Guard against regressions: optimized should not be slower than original by more than 5%.
    assert opt_time <= orig_time * 1.05,
           "Optimized encoder regressed: opt=#{opt_time}µs, orig=#{orig_time}µs"
  end
end
