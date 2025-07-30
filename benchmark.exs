# Performance benchmark for Gorilla Stream compression optimizations

alias GorillaStream.Compression.Gorilla.Encoder
alias GorillaStream.Compression.Gorilla.Decoder

defmodule Benchmark do
  def run do
    IO.puts("=== Gorilla Stream Performance Benchmark ===\n")

    # Test different dataset sizes
    sizes = [1_000, 10_000, 100_000, 500_000]

    for size <- sizes do
      IO.puts("Dataset size: #{size} points")

      # Generate test data
      data = generate_test_data(size)

      # Benchmark regular encoding
      {regular_time, {:ok, regular_result}} =
        :timer.tc(fn -> Encoder.encode(data) end)

      # Benchmark fast encoding
      {fast_time, {:ok, fast_result}} =
        :timer.tc(fn -> Encoder.encode_fast(data) end)

      # Verify results are identical
      results_match = regular_result == fast_result

      # Benchmark decoding
      {decode_time, {:ok, _decoded}} =
        :timer.tc(fn -> Decoder.decode(regular_result) end)

      # Calculate rates
      regular_rate = size / (regular_time / 1_000_000)
      fast_rate = size / (fast_time / 1_000_000)
      decode_rate = size / (decode_time / 1_000_000)

      improvement = regular_time / fast_time

      IO.puts("  Regular encode: #{regular_time}μs (#{Float.round(regular_rate, 0)} points/sec)")
      IO.puts("  Fast encode:    #{fast_time}μs (#{Float.round(fast_rate, 0)} points/sec)")
      IO.puts("  Decode:         #{decode_time}μs (#{Float.round(decode_rate, 0)} points/sec)")
      IO.puts("  Improvement:    #{Float.round(improvement, 2)}x faster")
      IO.puts("  Results match:  #{results_match}")
      IO.puts("  Compressed:     #{byte_size(regular_result)} bytes")
      IO.puts("")
    end

    # Memory benchmark
    IO.puts("=== Memory Usage Benchmark ===")
    large_data = generate_test_data(1_000_000)

    :erlang.garbage_collect()
    memory_before = :erlang.memory(:total)

    {:ok, compressed} = Encoder.encode_fast(large_data)

    :erlang.garbage_collect()
    memory_after = :erlang.memory(:total)

    memory_used = memory_after - memory_before

    IO.puts("1M points compression:")
    IO.puts("  Memory used: #{memory_used} bytes")
    IO.puts("  Compressed size: #{byte_size(compressed)} bytes")
    IO.puts("  Compression ratio: #{Float.round(byte_size(compressed) / (1_000_000 * 16), 4)}")
  end

  defp generate_test_data(size) do
    # Generate realistic time series data
    base_time = 1_609_459_200
    base_value = 100.0

    1..size
    |> Enum.map(fn i ->
      timestamp = base_time + i
      # Add some variation to make it realistic
      value = base_value + :math.sin(i * 0.01) * 10 + :rand.uniform() * 2
      {timestamp, value}
    end)
  end
end

# Run the benchmark
Benchmark.run()
