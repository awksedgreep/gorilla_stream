defmodule GorillaStream.Performance.StressTest do
  use ExUnit.Case, async: false
  @moduletag :stress
  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  describe "stress testing" do
    test "memory leak detection with repeated operations" do
      # Test for memory leaks over many iterations
      initial_data = generate_test_data(1000)

      # Get baseline memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Perform many encode/decode cycles
      iterations = 100

      for i <- 1..iterations do
        assert {:ok, compressed} = Encoder.encode(initial_data)
        assert {:ok, decompressed} = Decoder.decode(compressed)
        assert decompressed == initial_data

        # Force garbage collection every 10 iterations
        if rem(i, 10) == 0 do
          :erlang.garbage_collect()
          current_memory = :erlang.memory(:total)
          memory_growth = current_memory - initial_memory

          IO.puts("Iteration #{i}: Memory growth: #{memory_growth} bytes")

          # Memory growth should be reasonable (allow for some growth but not unlimited)
          assert memory_growth < 50_000_000,
                 "Memory growth after #{i} iterations should be under 50MB"
        end
      end

      # Final memory check
      :erlang.garbage_collect()
      final_memory = :erlang.memory(:total)
      total_growth = final_memory - initial_memory

      IO.puts("\n=== Memory Leak Test Results ===")
      IO.puts("Initial memory: #{initial_memory} bytes")
      IO.puts("Final memory: #{final_memory} bytes")
      IO.puts("Total growth: #{total_growth} bytes")
      IO.puts("Growth per iteration: #{Float.round(total_growth / iterations, 2)} bytes")

      # Assert reasonable memory usage
      assert total_growth < 100_000_000, "Total memory growth should be under 100MB"
    end

    @tag timeout: 120_000
    test "large dataset processing (1M+ points)" do
      # Test with very large datasets
      large_data = generate_large_dataset(1_000_000)

      IO.puts("\n=== Large Dataset Test (1M points) ===")
      IO.puts("Generated #{length(large_data)} data points")

      # Measure compression time
      {encode_time, {:ok, compressed}} =
        :timer.tc(fn ->
          Encoder.encode(large_data)
        end)

      compression_ratio = byte_size(compressed) / (length(large_data) * 16)

      IO.puts("Compression time: #{Float.round(encode_time / 1_000_000, 2)} seconds")
      IO.puts("Compressed size: #{byte_size(compressed)} bytes")
      IO.puts("Compression ratio: #{Float.round(compression_ratio, 4)}")

      # Measure decompression time
      {decode_time, {:ok, decompressed}} =
        :timer.tc(fn ->
          Decoder.decode(compressed)
        end)

      IO.puts("Decompression time: #{Float.round(decode_time / 1_000_000, 2)} seconds")

      # Verify correctness (sample check to avoid excessive comparison time)
      sample_indices = [0, 100_000, 500_000, 999_999]

      for index <- sample_indices do
        assert Enum.at(decompressed, index) == Enum.at(large_data, index),
               "Sample point #{index} should match after round-trip"
      end

      # Performance assertions
      assert encode_time < 60_000_000, "1M points should encode in under 60 seconds"
      assert decode_time < 60_000_000, "1M points should decode in under 60 seconds"
      assert compression_ratio < 1.0, "Should achieve some compression"

      IO.puts("Large dataset test completed successfully")
    end

    test "concurrent stress test with many processes" do
      # Test system under concurrent load
      process_count = 20
      operations_per_process = 50
      data_per_operation = generate_test_data(500)

      IO.puts("\n=== Concurrent Stress Test ===")
      IO.puts("Processes: #{process_count}")
      IO.puts("Operations per process: #{operations_per_process}")

      # Create many concurrent processes
      tasks =
        for i <- 1..process_count do
          Task.async(fn ->
            results =
              for j <- 1..operations_per_process do
                # Each operation: encode -> decode -> verify
                start_time = :os.system_time(:microsecond)

                assert {:ok, compressed} = Encoder.encode(data_per_operation)
                assert {:ok, decompressed} = Decoder.decode(compressed)
                assert decompressed == data_per_operation

                end_time = :os.system_time(:microsecond)
                operation_time = end_time - start_time

                {i, j, operation_time, byte_size(compressed)}
              end

            {i, results}
          end)
        end

      # Wait for all tasks to complete with extended timeout
      # 5 minutes timeout
      all_results = Task.await_many(tasks, 300_000)

      # Analyze results
      all_operations = Enum.flat_map(all_results, fn {_process_id, results} -> results end)

      total_operations = length(all_operations)
      total_time = Enum.sum(Enum.map(all_operations, fn {_, _, time, _} -> time end))
      avg_time = total_time / total_operations

      compressed_sizes = Enum.map(all_operations, fn {_, _, _, size} -> size end)
      avg_compressed_size = Enum.sum(compressed_sizes) / length(compressed_sizes)

      IO.puts("Total operations completed: #{total_operations}")
      IO.puts("Average operation time: #{Float.round(avg_time / 1000, 2)}ms")
      IO.puts("Average compressed size: #{Float.round(avg_compressed_size, 0)} bytes")
      IO.puts("All concurrent operations completed successfully")

      # Assert reasonable performance under load
      assert avg_time < 100_000, "Average operation time should be under 100ms"

      assert total_operations == process_count * operations_per_process,
             "All operations should complete"
    end

    test "error resilience under stress" do
      # Test error handling under various stress conditions
      valid_data = generate_test_data(1000)
      {:ok, valid_compressed} = Encoder.encode(valid_data)

      stress_scenarios = [
        {"massive_invalid_data", generate_invalid_data_scenarios()},
        {"corrupted_compressed_data", generate_corrupted_compressed_data(valid_compressed)},
        {"boundary_value_stress", generate_boundary_value_data()},
        {"malformed_input_stress", generate_malformed_inputs()}
      ]

      for {scenario_name, test_cases} <- stress_scenarios do
        IO.puts("\n--- Testing #{scenario_name} ---")

        {success_count, error_count} =
          Enum.reduce(test_cases, {0, 0}, fn test_case, {success_acc, error_acc} ->
            case test_case do
              {:encode, data} ->
                case Encoder.encode(data) do
                  {:ok, _} -> {success_acc + 1, error_acc}
                  {:error, _} -> {success_acc, error_acc + 1}
                end

              {:decode, compressed_data} ->
                case Decoder.decode(compressed_data) do
                  {:ok, _} -> {success_acc + 1, error_acc}
                  {:error, _} -> {success_acc, error_acc + 1}
                end
            end
          end)

        total_cases = length(test_cases)

        IO.puts(
          "#{scenario_name}: #{success_count} success, #{error_count} errors out of #{total_cases}"
        )

        # System should handle errors gracefully without crashing
        assert success_count + error_count == total_cases, "All cases should be handled"
      end

      IO.puts("Error resilience test completed - system remained stable")
    end

    test "sustained load test" do
      # Test continuous operation with optimized approach
      # Use iteration-based test instead of time-based for consistent performance
      target_operations = 1000
      # Larger dataset reduces overhead ratio
      data_set = generate_test_data(1000)

      IO.puts("\n=== Sustained Load Test (#{target_operations} operations) ===")

      # Pre-compile the operation to avoid first-call overhead
      {:ok, _} = Encoder.encode(data_set)

      # Batch operations to reduce measurement overhead
      batch_size = 50
      num_batches = div(target_operations, batch_size)

      {total_time, {total_encode_time, total_decode_time}} =
        :timer.tc(fn ->
          Enum.reduce(1..num_batches, {0, 0}, fn batch_num, {acc_encode, acc_decode} ->
            # Time a batch of operations instead of individual ones
            {batch_encode_time, compressed_results} =
              :timer.tc(fn ->
                Enum.map(1..batch_size, fn _ -> Encoder.encode(data_set) end)
              end)

            {batch_decode_time, decoded_results} =
              :timer.tc(fn ->
                Enum.map(compressed_results, fn {:ok, compressed} ->
                  Decoder.decode(compressed)
                end)
              end)

            # Validate one sample per batch instead of every operation
            if rem(batch_num, 10) == 1 do
              {:ok, sample_decode} = Enum.at(decoded_results, 0)
              assert length(sample_decode) == length(data_set)
            end

            if rem(batch_num * batch_size, 200) == 0 do
              IO.puts("Completed #{batch_num * batch_size} operations...")
            end

            {acc_encode + batch_encode_time, acc_decode + batch_decode_time}
          end)
        end)

      final_count = num_batches * batch_size
      operations_per_second = final_count / (total_time / 1_000_000)
      avg_encode_time = total_encode_time / final_count
      avg_decode_time = total_decode_time / final_count

      IO.puts("Operations completed: #{final_count}")
      IO.puts("Total test time: #{Float.round(total_time / 1_000_000, 2)}s")
      IO.puts("Operations per second: #{Float.round(operations_per_second, 2)}")
      IO.puts("Average encode time: #{Float.round(avg_encode_time / 1000, 2)}ms")
      IO.puts("Average decode time: #{Float.round(avg_decode_time / 1000, 2)}ms")

      # Performance assertions - more realistic for larger datasets
      assert operations_per_second > 50, "Should handle at least 50 operations per second"
      assert avg_encode_time < 20_000, "Average encode time should be under 20ms"
      assert avg_decode_time < 10_000, "Average decode time should be under 10ms"

      IO.puts("Sustained load test completed successfully")
    end
  end

  # Helper functions for generating test data

  defp generate_test_data(count) do
    base_timestamp = 1_609_459_200

    for i <- 0..(count - 1) do
      {base_timestamp + i, 100.0 + i * 0.1 + :math.sin(i * 0.1)}
    end
  end

  defp generate_large_dataset(count) do
    base_timestamp = 1_609_459_200
    # Use a more efficient approach for large datasets
    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(count)
    |> Stream.map(fn i ->
      # Realistic sensor data pattern
      # 24-hour cycle
      daily_cycle = 5.0 * :math.sin(i * 2 * :math.pi() / 1440)
      # Deterministic "noise"
      noise = rem(i, 100) / 1000.0
      temperature = 20.0 + daily_cycle + noise
      # Every minute
      {base_timestamp + i * 60, temperature}
    end)
    |> Enum.to_list()
  end

  defp generate_invalid_data_scenarios() do
    [
      # Invalid data types
      {:encode, "not_a_list"},
      {:encode, 12345},
      {:encode, %{invalid: "map"}},
      {:encode, :invalid_atom},

      # Invalid tuple structures
      # Too many elements
      {:encode, [{1, 2, 3}]},
      # Empty tuple
      {:encode, [{}]},
      # Single element
      {:encode, [{1}]},

      # Invalid timestamp types
      # Float timestamp
      {:encode, [{1.5, 2.0}]},
      # String timestamp
      {:encode, [{"string", 2.0}]},
      # Atom timestamp
      {:encode, [{:atom, 2.0}]},

      # Invalid value types
      # String value
      {:encode, [{1, "string"}]},
      # Atom value
      {:encode, [{1, :atom}]},
      # List value
      {:encode, [{1, [1, 2, 3]}]}
    ]
  end

  defp generate_corrupted_compressed_data(valid_compressed) do
    size = byte_size(valid_compressed)

    [
      # Truncated data
      {:decode, binary_part(valid_compressed, 0, div(size, 4))},
      {:decode, binary_part(valid_compressed, 0, div(size, 2))},

      # Corrupted headers
      {:decode, corrupt_bytes(valid_compressed, 0, 8)},
      {:decode, corrupt_bytes(valid_compressed, 8, 8)},

      # Corrupted middle sections
      {:decode, corrupt_bytes(valid_compressed, div(size, 3), 10)},
      {:decode, corrupt_bytes(valid_compressed, div(size, 2), 10)},

      # Random garbage
      {:decode, :crypto.strong_rand_bytes(size)},
      # All zeros
      {:decode, <<0::size(size * 8)>>},
      # All ones
      {:decode, <<255::size(size * 8)>>}
    ]
  end

  defp generate_boundary_value_data() do
    max_int = 9_223_372_036_854_775_807
    min_int = -9_223_372_036_854_775_808
    max_float = 1.7976931348623157e308
    min_float = -1.7976931348623157e308
    min_positive = 4.9e-324

    [
      # Timestamp boundaries
      {:encode, [{0, 1.0}]},
      {:encode, [{max_int, 1.0}]},
      {:encode, [{min_int, 1.0}]},

      # Float value boundaries
      {:encode, [{1_609_459_200, 0.0}]},
      {:encode, [{1_609_459_200, max_float}]},
      {:encode, [{1_609_459_200, min_float}]},
      {:encode, [{1_609_459_200, min_positive}]},

      # Large datasets
      {:encode, List.duplicate({1_609_459_200, 42.0}, 100_000)}
    ]
  end

  defp generate_malformed_inputs() do
    [
      # Empty binary
      {:decode, <<>>},
      # Too short
      {:decode, <<1, 2, 3>>},
      # String instead of binary
      {:decode, <<"invalid string">>},
      # Empty list (should be valid)
      {:encode, []},
      # Nil input
      {:encode, nil}
    ]
  end

  defp corrupt_bytes(binary, start_pos, count) do
    size = byte_size(binary)

    if start_pos + count > size do
      binary
    else
      <<prefix::binary-size(start_pos), _corrupted::binary-size(count), suffix::binary>> = binary
      random_bytes = :crypto.strong_rand_bytes(count)
      <<prefix::binary, random_bytes::binary, suffix::binary>>
    end
  end
end
