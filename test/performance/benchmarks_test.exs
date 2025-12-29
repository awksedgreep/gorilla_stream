defmodule GorillaStream.Performance.BenchmarksTest do
  use ExUnit.Case, async: false
  require Logger
  @moduletag :performance
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  @moduletag :performance

  describe "performance benchmarks" do
    test "compression ratio analysis across different data patterns" do
      # Test different data patterns and their compression ratios
      test_patterns = %{
        "identical_values" => generate_identical_values(1000),
        "gradual_increase" => generate_gradual_increase(1000),
        "random_walk" => generate_random_walk(1000),
        "sine_wave" => generate_sine_wave(1000),
        "step_function" => generate_step_function(1000),
        "high_frequency" => generate_high_frequency(1000)
      }

      for {pattern_name, data} <- test_patterns do
        # Measure compression
        {encode_time, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
        {decode_time, {:ok, _decompressed}} = :timer.tc(fn -> Decoder.decode(compressed) end)

        # 8 bytes timestamp + 8 bytes float
        original_size = length(data) * 16
        compressed_size = byte_size(compressed)
        compression_ratio = compressed_size / original_size

        result = %{
          encode_time_us: encode_time,
          decode_time_us: decode_time,
          original_size: original_size,
          compressed_size: compressed_size,
          compression_ratio: compression_ratio,
          data_points: length(data)
        }

        _results = Map.put(%{}, pattern_name, result)

        # Assertions for reasonable performance
        assert compression_ratio <= 1.0, "#{pattern_name}: Compression ratio should be <= 1.0"

        assert encode_time < 100_000,
               "#{pattern_name}: Encoding should be under 100ms for 1000 points"

        assert decode_time < 100_000,
               "#{pattern_name}: Decoding should be under 100ms for 1000 points"

        Logger.info("\n=== #{pattern_name} ===")
        Logger.info("Compression ratio: #{Float.round(compression_ratio, 4)}")
        Logger.info("Encode time: #{encode_time}μs (#{Float.round(encode_time / 1000, 2)}ms)")
        Logger.info("Decode time: #{decode_time}μs (#{Float.round(decode_time / 1000, 2)}ms)")
        Logger.info("Original size: #{original_size} bytes")
        Logger.info("Compressed size: #{compressed_size} bytes")
      end

      # Performance tests completed successfully
      Logger.info("All compression ratio tests completed")
    end

    test "VictoriaMetrics preprocessing performance (gauge and counter)" do
      require Logger
      gauge = generate_gradual_increase(5000)
      base = 1_700_000_000
      vals = Enum.scan(1..5000, 1_000.0, fn _, acc -> acc + (:rand.uniform(5) - 1) end)
      counter = Enum.with_index(vals, fn v, i -> {base + i, v + 0.01} end)

      # Gauge
      {g_b_t, {:ok, g_b}} = :timer.tc(fn -> Encoder.encode(gauge) end)
      {g_vm_t, {:ok, g_vm}} = :timer.tc(fn -> Encoder.encode(gauge, victoria_metrics: true, is_counter: false, scale_decimals: :auto) end)
      g_orig = length(gauge) * 16
      Logger.info("[VM gauge] baseline_ratio=#{Float.round(byte_size(g_b) / g_orig, 4)} vm_ratio=#{Float.round(byte_size(g_vm) / g_orig, 4)} baseline_us=#{g_b_t} vm_us=#{g_vm_t}")

      # Counter
      {c_b_t, {:ok, c_b}} = :timer.tc(fn -> Encoder.encode(counter) end)
      {c_vm_t, {:ok, c_vm}} = :timer.tc(fn -> Encoder.encode(counter, victoria_metrics: true, is_counter: true, scale_decimals: :auto) end)
      c_orig = length(counter) * 16
      Logger.info("[VM counter] baseline_ratio=#{Float.round(byte_size(c_b) / c_orig, 4)} vm_ratio=#{Float.round(byte_size(c_vm) / c_orig, 4)} baseline_us=#{c_b_t} vm_us=#{c_vm_t}")

      # Sanity: VM should not be worse by more than a factor on typical data
      assert byte_size(g_vm) <= byte_size(g_b) * 1.05
      assert byte_size(c_vm) <= byte_size(c_b) * 1.05
    end

    test "scalability testing with various dataset sizes" do
      sizes = [100, 500, 1000, 5000, 10000]

      for size <- sizes do
        data =
          GorillaStream.Performance.RealisticData.generate(size, :temperature,
            interval: 60,
            seed: {1, 2, 3}
          )

        # Measure compression performance
        {encode_time, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
        {decode_time, {:ok, decompressed}} = :timer.tc(fn -> Decoder.decode(compressed) end)

        # Verify correctness
        assert decompressed == data, "Round-trip should be lossless for #{size} points"

        # Performance assertions
        # points per second
        encode_rate = size / (encode_time / 1_000_000)
        # points per second
        decode_rate = size / (decode_time / 1_000_000)

        assert encode_rate > 1000,
               "Should encode at least 1000 points/sec (got #{Float.round(encode_rate, 0)})"

        assert decode_rate > 1000,
               "Should decode at least 1000 points/sec (got #{Float.round(decode_rate, 0)})"

        compression_ratio = byte_size(compressed) / (size * 16)

        Logger.info("\n=== Dataset size: #{size} points ===")
        Logger.info("Encode rate: #{Float.round(encode_rate, 0)} points/sec")
        Logger.info("Decode rate: #{Float.round(decode_rate, 0)} points/sec")
        Logger.info("Compression ratio: #{Float.round(compression_ratio, 4)}")
        Logger.info("Memory usage: #{byte_size(compressed)} bytes compressed")
      end
    end

    test "memory usage profiling" do
      # Test memory usage with large datasets
      large_data =
        GorillaStream.Performance.RealisticData.generate(50_000, :temperature,
          interval: 60,
          seed: {1, 2, 3}
        )

      # Measure memory before
      :erlang.garbage_collect()
      memory_before = :erlang.memory(:total)

      # Perform compression
      assert {:ok, compressed} = Encoder.encode(large_data)

      # Measure memory after compression
      :erlang.garbage_collect()
      memory_after_encode = :erlang.memory(:total)

      # Perform decompression
      assert {:ok, decompressed} = Decoder.decode(compressed)

      # Measure memory after decompression
      :erlang.garbage_collect()
      memory_after_decode = :erlang.memory(:total)

      # Verify correctness
      assert decompressed == large_data

      encode_memory_usage = memory_after_encode - memory_before
      total_memory_usage = memory_after_decode - memory_before

      Logger.info("\n=== Memory Usage Analysis (50K points) ===")
      Logger.info("Memory before: #{memory_before} bytes")
      Logger.info("Memory after encode: #{memory_after_encode} bytes")
      Logger.info("Memory after decode: #{memory_after_decode} bytes")
      Logger.info("Encode memory usage: #{encode_memory_usage} bytes")
      Logger.info("Total memory usage: #{total_memory_usage} bytes")
      Logger.info("Data size: #{length(large_data)} points")
      Logger.info("Compressed size: #{byte_size(compressed)} bytes")

      # Memory usage should be reasonable
      memory_per_point = total_memory_usage / length(large_data)

      assert memory_per_point < 200,
             "Memory usage per point should be reasonable (got #{Float.round(memory_per_point, 2)} bytes/point)"
    end

    test "concurrent compression/decompression stress test" do
      # Test concurrent operations to ensure thread safety
      data_sets =
        for i <- 1..10 do
          # Different sizes, deterministic seed per set
          GorillaStream.Performance.RealisticData.generate(1000 + i * 100, :temperature,
            interval: 60,
            seed: {i, 2, 3}
          )
        end

      # Concurrent compression
      compression_tasks =
        for {data, index} <- Enum.with_index(data_sets) do
          Task.async(fn ->
            {time, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
            {index, compressed, time}
          end)
        end

      compression_results = Task.await_many(compression_tasks, 10_000)

      # Concurrent decompression
      decompression_tasks =
        for {index, compressed, _encode_time} <- compression_results do
          original_data = Enum.at(data_sets, index)

          Task.async(fn ->
            {time, {:ok, decompressed}} = :timer.tc(fn -> Decoder.decode(compressed) end)
            {index, decompressed, original_data, time}
          end)
        end

      decompression_results = Task.await_many(decompression_tasks, 10_000)

      # Verify all results
      for {index, decompressed, original_data, _decode_time} <- decompression_results do
        assert decompressed == original_data,
               "Concurrent operation #{index} should maintain data integrity"
      end

      avg_encode_time =
        compression_results
        |> Enum.map(&elem(&1, 2))
        |> Enum.sum()
        |> div(length(compression_results))

      avg_decode_time =
        decompression_results
        |> Enum.map(&elem(&1, 3))
        |> Enum.sum()
        |> div(length(decompression_results))

      Logger.info("\n=== Concurrent Performance (10 tasks) ===")
      Logger.info("Average encode time: #{avg_encode_time}μs")
      Logger.info("Average decode time: #{avg_decode_time}μs")
      Logger.info("All concurrent operations completed successfully")
    end

    test "comparison with uncompressed storage" do
      # Compare Gorilla compression with simple binary storage
      test_data =
        GorillaStream.Performance.RealisticData.generate(5000, :temperature,
          interval: 60,
          seed: {1, 2, 3}
        )

      # Gorilla compression
      {gorilla_encode_time, {:ok, gorilla_compressed}} =
        :timer.tc(fn ->
          Encoder.encode(test_data)
        end)

      {gorilla_decode_time, {:ok, gorilla_decompressed}} =
        :timer.tc(fn ->
          Decoder.decode(gorilla_compressed)
        end)

      # Simple binary storage (baseline)
      {binary_encode_time, binary_data} =
        :timer.tc(fn ->
          :erlang.term_to_binary(test_data)
        end)

      {binary_decode_time, binary_decompressed} =
        :timer.tc(fn ->
          :erlang.binary_to_term(binary_data)
        end)

      # Zlib compression (alternative)
      {zlib_encode_time, zlib_compressed} =
        :timer.tc(fn ->
          :zlib.compress(:erlang.term_to_binary(test_data))
        end)

      {zlib_decode_time, zlib_decompressed_binary} =
        :timer.tc(fn ->
          :zlib.uncompress(zlib_compressed)
        end)

      zlib_decompressed = :erlang.binary_to_term(zlib_decompressed_binary)

      # Verify correctness
      assert gorilla_decompressed == test_data
      assert binary_decompressed == test_data
      assert zlib_decompressed == test_data

      # Calculate metrics
      original_size = length(test_data) * 16
      gorilla_ratio = byte_size(gorilla_compressed) / original_size
      binary_ratio = byte_size(binary_data) / original_size
      zlib_ratio = byte_size(zlib_compressed) / original_size

      Logger.info("\n=== Compression Comparison (5K sensor points) ===")
      Logger.info("Original size: #{original_size} bytes")
      Logger.info("")
      Logger.info("Gorilla:")

Logger.info(
        "  Size: #{byte_size(gorilla_compressed)} bytes (ratio: #{Float.round(gorilla_ratio, 4)})"
      )

      Logger.info("  Encode: #{gorilla_encode_time}μs, Decode: #{gorilla_decode_time}μs")
      Logger.info("")
      Logger.info("Binary (baseline):")
      Logger.info("  Size: #{byte_size(binary_data)} bytes (ratio: #{Float.round(binary_ratio, 4)})")
      Logger.info("  Encode: #{binary_encode_time}μs, Decode: #{binary_decode_time}μs")
      Logger.info("")
      Logger.info("Zlib:")

      Logger.info(
        "  Size: #{byte_size(zlib_compressed)} bytes (ratio: #{Float.round(zlib_ratio, 4)})"
      )

      Logger.info("  Encode: #{zlib_encode_time}μs, Decode: #{zlib_decode_time}μs")

      # Gorilla should be competitive
      assert gorilla_ratio < binary_ratio, "Gorilla should compress better than raw binary"
      assert gorilla_ratio <= zlib_ratio * 1.5, "Gorilla should be competitive with zlib"
    end

    test "edge case performance" do
      # Test performance with challenging datasets
      edge_cases = %{
        "all_zeros" => List.duplicate({1_609_459_200, 0.0}, 1000),
        "alternating" => generate_alternating_pattern(1000),
        "extreme_values" => generate_extreme_values(1000),
        "high_precision" => generate_high_precision_values(1000)
      }

      for {case_name, data} <- edge_cases do
        {encode_time, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
        {decode_time, {:ok, decompressed}} = :timer.tc(fn -> Decoder.decode(compressed) end)

        assert decompressed == data, "#{case_name}: Round-trip should be lossless"

        compression_ratio = byte_size(compressed) / (length(data) * 16)

        # Performance should be reasonable even for edge cases
        assert encode_time < 50_000, "#{case_name}: Encoding should be under 50ms"
        assert decode_time < 50_000, "#{case_name}: Decoding should be under 50ms"

        Logger.info("\n=== Edge Case: #{case_name} ===")
        Logger.info("Compression ratio: #{Float.round(compression_ratio, 4)}")
        Logger.info("Encode time: #{encode_time}μs")
        Logger.info("Decode time: #{decode_time}μs")
      end
    end
  end

  # Helper functions for generating test data

  defp generate_identical_values(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      {base_timestamp + i, 42.5}
    end
  end

  defp generate_gradual_increase(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      {base_timestamp + i, 100.0 + i * 0.1}
    end
  end

  defp generate_random_walk(count) do
    base_timestamp = 1_609_459_200
    # Deterministic for testing
    :rand.seed(:exsss, {1, 2, 3})

    {_, data} =
      Enum.reduce(0..(count - 1), {100.0, []}, fn i, {current_value, acc} ->
        # -1.0 to 1.0
        change = (:rand.uniform() - 0.5) * 2.0
        new_value = current_value + change
        new_point = {base_timestamp + i, new_value}
        {new_value, [new_point | acc]}
      end)

    Enum.reverse(data)
  end

  defp generate_sine_wave(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      value = 100.0 + 50.0 * :math.sin(i * 0.1)
      {base_timestamp + i, value}
    end
  end

  defp generate_step_function(count) do
    base_timestamp = 1_609_459_200
    step_size = div(count, 5)

    for i <- 0..(count - 1) do
      step = div(i, step_size)
      value = (step + 1) * 10.0
      {base_timestamp + i, value}
    end
  end

  defp generate_high_frequency(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      value = 100.0 + 10.0 * :math.sin(i * 0.5) + 2.0 * :math.sin(i * 1.3)
      {base_timestamp + i, value}
    end
  end


  defp generate_alternating_pattern(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      value = if rem(i, 2) == 0, do: 100.0, else: 200.0
      {base_timestamp + i, value}
    end
  end

  defp generate_extreme_values(count) do
    base_timestamp = 1_609_459_200

    values = [
      # Max float
      1.7976931348623157e308,
      # Min normal
      2.2250738585072014e-308,
      # Min subnormal
      4.9e-324,
      0.0,
      # Min float
      -1.7976931348623157e308
    ]

    for i <- 0..(count - 1) do
      value = Enum.at(values, rem(i, length(values)))
      {base_timestamp + i, value}
    end
  end

  defp generate_high_precision_values(count) do
    base_timestamp = 1_609_459_200
    base_value = 1.23456789012345

    for i <- 0..(count - 1) do
      value = base_value + i * 1.0e-14
      {base_timestamp + i, value}
    end
  end
end
