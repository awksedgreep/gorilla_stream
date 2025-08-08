defmodule GorillaStream.Performance.RealisticDataGeneratorTest do
  use ExUnit.Case, async: false

  describe "realistic data generator" do
    @describetag :performance
    @tag :performance
    test "generate 1000 sensor data points efficiently" do
      count = 1000
      
      # Measure generation time and memory usage
      {generation_time, data} = :timer.tc(fn ->
        generate_realistic_sensor_data(count)
      end)
      
      # Verify data structure and count
      assert length(data) == count
      assert is_list(data)
      
      # Verify each tuple has correct structure {timestamp, value}
      Enum.each(data, fn item ->
        assert {timestamp, value} = item
        assert is_integer(timestamp)
        assert is_float(value)
      end)
      
      # Verify timestamps are sequential
      timestamps = Enum.map(data, &elem(&1, 0))
      sorted_timestamps = Enum.sort(timestamps)
      assert timestamps == sorted_timestamps
      
      IO.puts("Generated #{count} data points in #{Float.round(generation_time / 1000, 2)}ms")
      
      # Performance assertion - should generate quickly
      assert generation_time < 50_000, "Generation should take less than 50ms (took #{generation_time}μs)"
    end

    @tag :performance
    test "generate 2500 sensor data points efficiently" do
      count = 2500
      
      {generation_time, data} = :timer.tc(fn ->
        generate_realistic_sensor_data(count)
      end)
      
      assert length(data) == count
      assert is_list(data)
      
      # Spot check data quality
      sample_values = data |> Enum.take(100) |> Enum.map(&elem(&1, 1))
      avg_value = Enum.sum(sample_values) / length(sample_values)
      
      # Should be around base temperature of 20.0
      assert avg_value > 18.0 and avg_value < 22.0
      
      IO.puts("Generated #{count} data points in #{Float.round(generation_time / 1000, 2)}ms")
      
      # Performance assertion
      assert generation_time < 100_000, "Generation should take less than 100ms (took #{generation_time}μs)"
    end

    @tag :performance
    test "generate 5000 sensor data points efficiently" do
      count = 5000
      
      {generation_time, data} = :timer.tc(fn ->
        generate_realistic_sensor_data(count)
      end)
      
      assert length(data) == count
      assert is_list(data)
      
      # Test data distribution - should follow realistic patterns
      values = Enum.map(data, &elem(&1, 1))
      min_value = Enum.min(values)
      max_value = Enum.max(values)
      
      # Temperature should vary in realistic range
      assert min_value > 14.0  # Should stay above 14°C
      assert max_value < 26.0  # Should stay below 26°C
      assert (max_value - min_value) > 8.0  # Should have good variation
      
      IO.puts("Generated #{count} data points in #{Float.round(generation_time / 1000, 2)}ms")
      IO.puts("Value range: #{Float.round(min_value, 2)}°C to #{Float.round(max_value, 2)}°C")
      
      # Performance assertion
      assert generation_time < 200_000, "Generation should take less than 200ms (took #{generation_time}μs)"
    end

    @tag :performance
    test "generate multiple datasets with low GC pressure" do
      # Test generating multiple datasets to verify low GC pressure
      dataset_count = 10
      points_per_dataset = 1000
      
      # Collect GC stats before
      gc_before = :erlang.statistics(:garbage_collection)
      
      {total_time, datasets} = :timer.tc(fn ->
        for _i <- 1..dataset_count do
          generate_realistic_sensor_data(points_per_dataset)
        end
      end)
      
      # Collect GC stats after
      gc_after = :erlang.statistics(:garbage_collection)
      
      # Calculate GC impact
      {gc_runs_before, words_reclaimed_before, _} = gc_before
      {gc_runs_after, words_reclaimed_after, _} = gc_after
      
      gc_runs = gc_runs_after - gc_runs_before
      words_reclaimed = words_reclaimed_after - words_reclaimed_before
      
      # Verify all datasets were generated correctly
      assert length(datasets) == dataset_count
      Enum.each(datasets, fn dataset ->
        assert length(dataset) == points_per_dataset
      end)
      
      total_points = dataset_count * points_per_dataset
      avg_time_per_dataset = total_time / dataset_count
      
      IO.puts("Generated #{dataset_count} datasets (#{total_points} total points)")
      IO.puts("Total time: #{Float.round(total_time / 1000, 2)}ms")
      IO.puts("Average time per dataset: #{Float.round(avg_time_per_dataset / 1000, 2)}ms")
      IO.puts("GC runs during generation: #{gc_runs}")
      IO.puts("Words reclaimed by GC: #{words_reclaimed}")
      
      # Performance assertions for low GC pressure
      assert avg_time_per_dataset < 50_000, "Each dataset should generate in <50ms"
      assert gc_runs < 100, "Should have reasonable GC pressure (got #{gc_runs} runs)"
    end

    @tag :performance
    test "generate large dataset with memory efficiency verification" do
      count = 5000
      
      # Monitor memory usage during generation
      memory_before = :erlang.memory(:total)
      
      {generation_time, data} = :timer.tc(fn ->
        generate_realistic_sensor_data(count)
      end)
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      assert length(data) == count
      
      # Calculate approximate memory per data point
      # Each tuple is {integer, float} ≈ 16 bytes + overhead
      memory_per_point = memory_used / count
      
      IO.puts("Generated #{count} data points using #{memory_used} bytes")
      IO.puts("Approx #{Float.round(memory_per_point, 1)} bytes per data point")
      IO.puts("Generation time: #{Float.round(generation_time / 1000, 2)}ms")
      
      # Memory efficiency assertions
      assert memory_per_point < 150, "Should use less than 150 bytes per data point (got #{Float.round(memory_per_point, 1)})"
      assert generation_time < 200_000, "Should generate in reasonable time"
    end

    @tag :performance
    test "verify data reproducibility with consistent seed" do
      count = 1000
      
      # Generate same dataset twice
      dataset1 = generate_realistic_sensor_data(count)
      dataset2 = generate_realistic_sensor_data(count)
      
      # Should be identical due to deterministic seed
      assert dataset1 == dataset2
      
      # Generate different dataset with different parameters
      dataset3 = generate_realistic_sensor_data_with_seed(count, {4, 5, 6})
      
      # Should be different with different seed
      refute dataset1 == dataset3
      
      IO.puts("Verified data reproducibility with deterministic seed")
    end
  end

  # Reuse the helper function from sustained_throughput_test.exs
  # This is the core function that efficiently generates realistic sensor data
  defp generate_realistic_sensor_data(count) do
    generate_realistic_sensor_data_with_seed(count, {1, 2, 3})
  end

  defp generate_realistic_sensor_data_with_seed(count, seed) do
    base_timestamp = 1_609_459_200
    # Deterministic seed for reproducible tests  
    :rand.seed(:exsss, seed)

    for i <- 0..(count - 1) do
      # Simulate realistic sensor data: base temperature + daily cycle + noise
      daily_cycle = 5.0 * :math.sin(i * 2 * :math.pi() / 1440)  # 24-hour cycle
      noise = (:rand.uniform() - 0.5) * 0.5  # ±0.25 degree noise
      temperature = 20.0 + daily_cycle + noise
      {base_timestamp + i * 60, temperature}  # Every minute
    end
  end
end
