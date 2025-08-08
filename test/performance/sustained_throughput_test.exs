defmodule GorillaStream.Performance.SustainedThroughputTest do
  use ExUnit.Case, async: false
  @tag :sustained_performance
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
  alias GorillaStream.Testing.MemoryLeakDetector

  describe "sustained throughput testing" do
    @tag :sustained_performance
    test "measure sustained encoding throughput over extended period" do
      # Test sustained encoding performance with continuous data streams
      data_points_per_batch = 1000
      total_batches = 100
      test_data = generate_realistic_sensor_data(data_points_per_batch)

      IO.puts("\n=== Sustained Encoding Throughput Test ===")
      IO.puts("Data points per batch: #{data_points_per_batch}")
      IO.puts("Total batches: #{total_batches}")
      IO.puts("Total data points: #{data_points_per_batch * total_batches}")

      # Warm up to avoid first-call overhead
      {:ok, _} = Encoder.encode(test_data)

      encode_times = []
      throughput_samples = []

      {total_test_time, {final_encode_times, final_throughput_samples}} =
        :timer.tc(fn ->
          Enum.reduce(1..total_batches, {[], []}, fn batch_num, {encode_acc, throughput_acc} ->
            # Generate fresh data for each batch to simulate real streaming
            batch_data = generate_time_shifted_data(test_data, batch_num * data_points_per_batch)

            {encode_time, {:ok, _compressed}} =
              :timer.tc(fn -> Encoder.encode(batch_data) end)

            # Calculate throughput for this batch (points per second)
            throughput = data_points_per_batch / (encode_time / 1_000_000)

            # Progress reporting every 10 batches
            if rem(batch_num, 10) == 0 do
              avg_throughput =
                Enum.sum(throughput_acc ++ [throughput]) / length(throughput_acc ++ [throughput])

              IO.puts(
                "Batch #{batch_num}/#{total_batches}: Current throughput: #{Float.round(throughput, 0)} pts/sec, Average: #{Float.round(avg_throughput, 0)} pts/sec"
              )
            end

            {[encode_time | encode_acc], [throughput | throughput_acc]}
          end)
        end)

      # Analyze sustained performance metrics
      total_points = data_points_per_batch * total_batches
      overall_throughput = total_points / (total_test_time / 1_000_000)

      avg_encode_time = Enum.sum(final_encode_times) / length(final_encode_times)
      min_encode_time = Enum.min(final_encode_times)
      max_encode_time = Enum.max(final_encode_times)

      avg_throughput = Enum.sum(final_throughput_samples) / length(final_throughput_samples)
      min_throughput = Enum.min(final_throughput_samples)
      max_throughput = Enum.max(final_throughput_samples)

      # Calculate throughput stability (coefficient of variation)
      throughput_stddev = calculate_stddev(final_throughput_samples)
      throughput_cv = throughput_stddev / avg_throughput

      IO.puts("\n=== Sustained Encoding Results ===")
      IO.puts("Test duration: #{Float.round(total_test_time / 1_000_000, 2)} seconds")
      IO.puts("Overall throughput: #{Float.round(overall_throughput, 0)} points/sec")
      IO.puts("Average throughput: #{Float.round(avg_throughput, 0)} points/sec")
      IO.puts("Min throughput: #{Float.round(min_throughput, 0)} points/sec")
      IO.puts("Max throughput: #{Float.round(max_throughput, 0)} points/sec")
      IO.puts("Throughput stability (CV): #{Float.round(throughput_cv * 100, 2)}%")
      IO.puts("Average encode time: #{Float.round(avg_encode_time / 1000, 2)}ms")
      IO.puts("Min encode time: #{Float.round(min_encode_time / 1000, 2)}ms")
      IO.puts("Max encode time: #{Float.round(max_encode_time / 1000, 2)}ms")

      # Performance assertions for sustained throughput
      assert overall_throughput > 5000,
             "Overall throughput should exceed 5000 points/sec (got #{Float.round(overall_throughput, 0)})"

      assert avg_throughput > 5000,
             "Average throughput should exceed 5000 points/sec (got #{Float.round(avg_throughput, 0)})"

      assert throughput_cv < 0.3,
             "Throughput should be stable with CV < 30% (got #{Float.round(throughput_cv * 100, 2)}%)"

      assert min_throughput > 1000,
             "Minimum throughput should exceed 1000 points/sec (got #{Float.round(min_throughput, 0)})"
    end

    @tag :sustained_performance
    test "measure sustained decoding throughput over extended period" do
      # Test sustained decoding performance with pre-compressed data
      data_points_per_batch = 1000
      total_batches = 100

      IO.puts("\n=== Sustained Decoding Throughput Test ===")
      IO.puts("Data points per batch: #{data_points_per_batch}")
      IO.puts("Total batches: #{total_batches}")

      # Pre-compress test data batches
      IO.puts("Pre-compressing test data...")

      compressed_batches =
        for batch_num <- 1..total_batches do
          test_data = generate_realistic_sensor_data(data_points_per_batch)
          batch_data = generate_time_shifted_data(test_data, batch_num * data_points_per_batch)
          {:ok, compressed} = Encoder.encode(batch_data)
          compressed
        end

      # Warm up decoder
      {:ok, _} = Decoder.decode(Enum.at(compressed_batches, 0))

      decode_times = []
      throughput_samples = []

      {total_test_time, {final_decode_times, final_throughput_samples}} =
        :timer.tc(fn ->
          Enum.with_index(compressed_batches)
          |> Enum.reduce({[], []}, fn {compressed_data, batch_num},
                                      {decode_acc, throughput_acc} ->
            {decode_time, {:ok, decompressed}} =
              :timer.tc(fn -> Decoder.decode(compressed_data) end)

            # Verify we got the expected number of points
            assert length(decompressed) == data_points_per_batch

            # Calculate throughput for this batch (points per second)
            throughput = data_points_per_batch / (decode_time / 1_000_000)

            # Progress reporting every 10 batches
            if rem(batch_num + 1, 10) == 0 do
              avg_throughput =
                Enum.sum(throughput_acc ++ [throughput]) / length(throughput_acc ++ [throughput])

              IO.puts(
                "Batch #{batch_num + 1}/#{total_batches}: Current throughput: #{Float.round(throughput, 0)} pts/sec, Average: #{Float.round(avg_throughput, 0)} pts/sec"
              )
            end

            {[decode_time | decode_acc], [throughput | throughput_acc]}
          end)
        end)

      # Analyze sustained decoding performance
      total_points = data_points_per_batch * total_batches
      overall_throughput = total_points / (total_test_time / 1_000_000)

      avg_decode_time = Enum.sum(final_decode_times) / length(final_decode_times)
      min_decode_time = Enum.min(final_decode_times)
      max_decode_time = Enum.max(final_decode_times)

      avg_throughput = Enum.sum(final_throughput_samples) / length(final_throughput_samples)
      min_throughput = Enum.min(final_throughput_samples)
      max_throughput = Enum.max(final_throughput_samples)

      # Calculate throughput stability
      throughput_stddev = calculate_stddev(final_throughput_samples)
      throughput_cv = throughput_stddev / avg_throughput

      IO.puts("\n=== Sustained Decoding Results ===")
      IO.puts("Test duration: #{Float.round(total_test_time / 1_000_000, 2)} seconds")
      IO.puts("Overall throughput: #{Float.round(overall_throughput, 0)} points/sec")
      IO.puts("Average throughput: #{Float.round(avg_throughput, 0)} points/sec")
      IO.puts("Min throughput: #{Float.round(min_throughput, 0)} points/sec")
      IO.puts("Max throughput: #{Float.round(max_throughput, 0)} points/sec")
      IO.puts("Throughput stability (CV): #{Float.round(throughput_cv * 100, 2)}%")
      IO.puts("Average decode time: #{Float.round(avg_decode_time / 1000, 2)}ms")
      IO.puts("Min decode time: #{Float.round(min_decode_time / 1000, 2)}ms")
      IO.puts("Max decode time: #{Float.round(max_decode_time / 1000, 2)}ms")

      # Performance assertions for sustained decoding throughput
      assert overall_throughput > 10000,
             "Overall decoding throughput should exceed 10000 points/sec (got #{Float.round(overall_throughput, 0)})"

      assert avg_throughput > 10000,
             "Average decoding throughput should exceed 10000 points/sec (got #{Float.round(avg_throughput, 0)})"

      assert throughput_cv < 0.3,
             "Decoding throughput should be stable with CV < 30% (got #{Float.round(throughput_cv * 100, 2)}%)"

      assert min_throughput > 2000,
             "Minimum decoding throughput should exceed 2000 points/sec (got #{Float.round(min_throughput, 0)})"
    end

    @tag :sustained_performance
    test "measure sustained round-trip throughput with pipeline processing" do
      # Test sustained round-trip performance simulating a real processing pipeline
      data_points_per_batch = 500
      total_batches = 50
      # Number of concurrent encode/decode operations
      pipeline_depth = 3

      IO.puts("\n=== Sustained Pipeline Throughput Test ===")
      IO.puts("Data points per batch: #{data_points_per_batch}")
      IO.puts("Total batches: #{total_batches}")
      IO.puts("Pipeline depth: #{pipeline_depth}")

      # Generate all test data upfront
      test_data_batches =
        for batch_num <- 1..total_batches do
          base_data = generate_realistic_sensor_data(data_points_per_batch)
          generate_time_shifted_data(base_data, batch_num * data_points_per_batch)
        end

      # Warm up
      sample_data = Enum.at(test_data_batches, 0)
      {:ok, sample_compressed} = Encoder.encode(sample_data)
      {:ok, _sample_decompressed} = Decoder.decode(sample_compressed)

      pipeline_results = []

      {total_test_time, final_results} =
        :timer.tc(fn ->
          test_data_batches
          |> Enum.chunk_every(pipeline_depth)
          |> Enum.with_index()
          |> Enum.flat_map(fn {batch_chunk, chunk_index} ->
            # Process pipeline chunk concurrently
            tasks =
              Enum.with_index(batch_chunk)
              |> Enum.map(fn {batch_data, batch_index} ->
                global_batch_num = chunk_index * pipeline_depth + batch_index + 1

                Task.async(fn ->
                  # Measure round-trip time
                  {round_trip_time, {:ok, decompressed}} =
                    :timer.tc(fn ->
                      {:ok, compressed} = Encoder.encode(batch_data)
                      Decoder.decode(compressed)
                    end)

                  # Verify correctness
                  assert length(decompressed) == length(batch_data)

                  # Calculate throughput
                  throughput = data_points_per_batch / (round_trip_time / 1_000_000)

                  {global_batch_num, round_trip_time, throughput, length(decompressed)}
                end)
              end)

            # Wait for pipeline chunk to complete
            chunk_results = Task.await_many(tasks, 30_000)

            # Report progress
            last_batch_num = elem(List.last(chunk_results), 0)

            if rem(last_batch_num, 10) == 0 do
              recent_throughputs = Enum.map(chunk_results, &elem(&1, 2))
              avg_recent_throughput = Enum.sum(recent_throughputs) / length(recent_throughputs)

              IO.puts(
                "Completed batch #{last_batch_num}/#{total_batches}: Recent avg throughput: #{Float.round(avg_recent_throughput, 0)} pts/sec"
              )
            end

            chunk_results
          end)
        end)

      # Analyze pipeline performance
      total_points = data_points_per_batch * total_batches
      overall_throughput = total_points / (total_test_time / 1_000_000)

      round_trip_times = Enum.map(final_results, &elem(&1, 1))
      throughput_samples = Enum.map(final_results, &elem(&1, 2))

      avg_round_trip_time = Enum.sum(round_trip_times) / length(round_trip_times)
      min_round_trip_time = Enum.min(round_trip_times)
      max_round_trip_time = Enum.max(round_trip_times)

      avg_throughput = Enum.sum(throughput_samples) / length(throughput_samples)
      min_throughput = Enum.min(throughput_samples)
      max_throughput = Enum.max(throughput_samples)

      # Calculate stability metrics
      throughput_stddev = calculate_stddev(throughput_samples)
      throughput_cv = throughput_stddev / avg_throughput

      IO.puts("\n=== Sustained Pipeline Results ===")
      IO.puts("Test duration: #{Float.round(total_test_time / 1_000_000, 2)} seconds")
      IO.puts("Overall throughput: #{Float.round(overall_throughput, 0)} points/sec")
      IO.puts("Average batch throughput: #{Float.round(avg_throughput, 0)} points/sec")
      IO.puts("Min batch throughput: #{Float.round(min_throughput, 0)} points/sec")
      IO.puts("Max batch throughput: #{Float.round(max_throughput, 0)} points/sec")
      IO.puts("Throughput stability (CV): #{Float.round(throughput_cv * 100, 2)}%")
      IO.puts("Average round-trip time: #{Float.round(avg_round_trip_time / 1000, 2)}ms")
      IO.puts("Min round-trip time: #{Float.round(min_round_trip_time / 1000, 2)}ms")
      IO.puts("Max round-trip time: #{Float.round(max_round_trip_time / 1000, 2)}ms")

      # Performance assertions for pipeline throughput
      assert overall_throughput > 2000,
             "Pipeline overall throughput should exceed 2000 points/sec (got #{Float.round(overall_throughput, 0)})"

      assert avg_throughput > 2000,
             "Pipeline average throughput should exceed 2000 points/sec (got #{Float.round(avg_throughput, 0)})"

      assert throughput_cv < 0.4,
             "Pipeline throughput should be reasonably stable with CV < 40% (got #{Float.round(throughput_cv * 100, 2)}%)"

      assert min_throughput > 500,
             "Minimum pipeline throughput should exceed 500 points/sec (got #{Float.round(min_throughput, 0)})"

      # Ensure all batches completed successfully
      assert length(final_results) == total_batches,
             "All #{total_batches} batches should complete successfully"
    end
  end

  # Helper functions for generating test data

  defp generate_realistic_sensor_data(count) do
    base_timestamp = 1_609_459_200
    # Deterministic seed for reproducible tests
    :rand.seed(:exsss, {1, 2, 3})

    for i <- 0..(count - 1) do
      # Simulate realistic sensor data: base temperature + daily cycle + noise
      # 24-hour cycle
      daily_cycle = 5.0 * :math.sin(i * 2 * :math.pi() / 1440)
      # ±0.25 degree noise
      noise = (:rand.uniform() - 0.5) * 0.5
      temperature = 20.0 + daily_cycle + noise
      # Every minute
      {base_timestamp + i * 60, temperature}
    end
  end

  defp generate_time_shifted_data(base_data, time_offset) do
    Enum.map(base_data, fn {timestamp, value} ->
      {timestamp + time_offset, value}
    end)
  end

  defp calculate_stddev(values) do
    count = length(values)

    if count <= 1 do
      0.0
    else
      mean = Enum.sum(values) / count

      variance =
        Enum.reduce(values, 0, fn x, acc ->
          diff = x - mean
          acc + diff * diff
        end) / (count - 1)

      :math.sqrt(variance)
    end
  end
end
