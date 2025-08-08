#!/usr/bin/env elixir

# This script should be run within the GorillaStream Mix project
# Usage: mix run five_minute_benchmark.exs

defmodule FiveMinuteBenchmark do
  @moduledoc """
  5-minute continuous benchmarking of Gorilla compression with both raw and zlib variants.
  
  This script runs for exactly 5 minutes, continuously generating datasets of random sizes
  between 1,000-5,000 points, then encoding and decoding with both raw Gorilla compression
  and zlib-enabled variants, accumulating performance counters.
  
  Features periodic metric snapshots every 10 seconds with operations per second and memory usage.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
  alias GorillaStream.Performance.MetricSnapshots

  def run() do
    IO.puts("Starting 5-minute Gorilla compression benchmark...")
    IO.puts("Dataset sizes: 1,000-5,000 points (random)")
    IO.puts("Testing both raw Gorilla and zlib-enabled variants")
    IO.puts("Periodic snapshots every 10 seconds with ops/sec and memory usage")
    IO.puts("=" |> String.duplicate(60))

    # Start the metric snapshot system
    {:ok, _pid} = MetricSnapshots.start_link()
    
    # Initialize counters
    initial_state = %{
      raw_enc_ops: 0,
      raw_dec_ops: 0, 
      z_enc_ops: 0,
      z_dec_ops: 0,
      raw_enc_time: 0,
      raw_dec_time: 0,
      z_enc_time: 0,
      z_dec_time: 0,
      total_datasets: 0
    }

    # Calculate 5-minute deadline
    deadline = System.monotonic_time(:millisecond) + 300_000

    IO.puts("Deadline set for: #{deadline} ms")
    IO.puts("Starting continuous benchmarking loop...\n")

    # Run the timing loop
    final_state = benchmark_loop(deadline, initial_state)

    # Stop metric snapshots and get final CSV report
    snapshots = MetricSnapshots.stop_and_get_snapshots()
    
    # Display final results
    display_results(final_state, snapshots)
  end

  defp benchmark_loop(deadline, state) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= deadline do
      state
    else
      # Generate dataset with random size between 1,000-5,000
      dataset_size = :rand.uniform(4000) + 1000
      dataset = generate_dataset(dataset_size)
      
      # Test raw Gorilla compression
      {raw_enc_time, {:ok, raw_compressed}} = :timer.tc(fn -> 
        Encoder.encode(dataset) 
      end)
      
      {raw_dec_time, {:ok, _raw_decompressed}} = :timer.tc(fn -> 
        Decoder.decode(raw_compressed) 
      end)
      
      # Test zlib-enabled Gorilla compression  
      {z_enc_time, {:ok, z_compressed}} = :timer.tc(fn ->
        GorillaStream.compress(dataset, true)
      end)
      
      {z_dec_time, {:ok, _z_decompressed}} = :timer.tc(fn ->
        GorillaStream.decompress(z_compressed, true)
      end)
      
      # Update counters
      new_state = %{
        raw_enc_ops: state.raw_enc_ops + 1,
        raw_dec_ops: state.raw_dec_ops + 1,
        z_enc_ops: state.z_enc_ops + 1, 
        z_dec_ops: state.z_dec_ops + 1,
        raw_enc_time: state.raw_enc_time + raw_enc_time,
        raw_dec_time: state.raw_dec_time + raw_dec_time,
        z_enc_time: state.z_enc_time + z_enc_time,
        z_dec_time: state.z_dec_time + z_dec_time,
        total_datasets: state.total_datasets + 1
      }

      # Update metric snapshots with current operation counts
      MetricSnapshots.update_ops_counters(%{
        raw_enc_ops: new_state.raw_enc_ops,
        raw_dec_ops: new_state.raw_dec_ops,
        z_enc_ops: new_state.z_enc_ops,
        z_dec_ops: new_state.z_dec_ops
      })

      # Print periodic updates every 100 datasets
      if rem(new_state.total_datasets, 100) == 0 do
        remaining = max(0, deadline - System.monotonic_time(:millisecond))
        IO.puts("Progress: #{new_state.total_datasets} datasets processed, #{div(remaining, 1000)}s remaining")
      end
      
      # Continue the loop
      benchmark_loop(deadline, new_state)
    end
  end

  defp generate_dataset(size) do
    base_timestamp = 1_609_459_200
    
    # Generate realistic time series data with gradual changes
    for i <- 0..(size - 1) do
      # Simulate sensor readings with small variations
      base_value = 100.0
      variation = :math.sin(i * 0.01) * 5.0  # Gradual sine wave
      noise = (:rand.uniform() - 0.5) * 0.5  # Small random noise
      value = base_value + variation + noise
      
      {base_timestamp + i * 60, value}  # Every minute
    end
  end

  defp display_results(state, snapshots) do
    IO.puts("\n" <> ("=" |> String.duplicate(60)))
    IO.puts("5-MINUTE BENCHMARK RESULTS")
    IO.puts("=" |> String.duplicate(60))
    
    IO.puts("Total datasets processed: #{state.total_datasets}")
    IO.puts("")
    
    IO.puts("RAW GORILLA COMPRESSION:")
    IO.puts("  Encode operations: #{state.raw_enc_ops}")
    IO.puts("  Decode operations: #{state.raw_dec_ops}")
    IO.puts("  Total encode time: #{div(state.raw_enc_time, 1000)} ms")
    IO.puts("  Total decode time: #{div(state.raw_dec_time, 1000)} ms")
    
    if state.raw_enc_ops > 0 do
      avg_enc_time = div(state.raw_enc_time, state.raw_enc_ops)
      avg_dec_time = div(state.raw_dec_time, state.raw_dec_ops)
      IO.puts("  Avg encode time: #{avg_enc_time} μs")
      IO.puts("  Avg decode time: #{avg_dec_time} μs")
    end
    
    IO.puts("")
    IO.puts("ZLIB-ENABLED GORILLA COMPRESSION:")
    IO.puts("  Encode operations: #{state.z_enc_ops}")
    IO.puts("  Decode operations: #{state.z_dec_ops}")
    IO.puts("  Total encode time: #{div(state.z_enc_time, 1000)} ms")
    IO.puts("  Total decode time: #{div(state.z_dec_time, 1000)} ms")
    
    if state.z_enc_ops > 0 do
      avg_enc_time = div(state.z_enc_time, state.z_enc_ops)
      avg_dec_time = div(state.z_dec_time, state.z_dec_ops)  
      IO.puts("  Avg encode time: #{avg_enc_time} μs")
      IO.puts("  Avg decode time: #{avg_dec_time} μs")
    end
    
    IO.puts("")
    IO.puts("PERFORMANCE SUMMARY:")
    total_ops = state.raw_enc_ops + state.raw_dec_ops + state.z_enc_ops + state.z_dec_ops
    IO.puts("  Total operations: #{total_ops}")
    IO.puts("  Operations per second: #{div(total_ops * 1000, 300_000)}")
    
    if state.raw_enc_ops > 0 and state.z_enc_ops > 0 do
      raw_avg_enc = div(state.raw_enc_time, state.raw_enc_ops)
      z_avg_enc = div(state.z_enc_time, state.z_enc_ops)
      overhead = ((z_avg_enc - raw_avg_enc) / raw_avg_enc * 100) |> Float.round(1)
      IO.puts("  Zlib encoding overhead: #{overhead}%")
      
      raw_avg_dec = div(state.raw_dec_time, state.raw_dec_ops)
      z_avg_dec = div(state.z_dec_time, state.z_dec_ops)
      overhead = ((z_avg_dec - raw_avg_dec) / raw_avg_dec * 100) |> Float.round(1)
      IO.puts("  Zlib decoding overhead: #{overhead}%")
    end
    
    # Display metric snapshots summary
    IO.puts("")
    IO.puts("METRIC SNAPSHOTS SUMMARY:")
    IO.puts("  Total snapshots captured: #{length(snapshots)}")
    
    if length(snapshots) > 0 do
      last_snapshot = List.last(snapshots)
      IO.puts("  Final memory usage: #{format_bytes(last_snapshot.total_memory_bytes)}")
      IO.puts("  Final total ops/sec: #{last_snapshot.raw_enc_ops_per_sec_cumulative + last_snapshot.raw_dec_ops_per_sec_cumulative + last_snapshot.z_enc_ops_per_sec_cumulative + last_snapshot.z_dec_ops_per_sec_cumulative}")
    end
    
    IO.puts("")
    IO.puts("CSV SNAPSHOT DATA:")
    IO.puts("=" |> String.duplicate(60))
    
    # Print CSV data
    print_csv_header()
    Enum.each(snapshots, &print_csv_row/1)
    
    IO.puts("")
    IO.puts("Benchmark completed successfully!")
  end
  
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
  
  defp print_csv_header do
    IO.puts("elapsed_seconds,raw_enc_ops_since_last,raw_dec_ops_since_last,z_enc_ops_since_last,z_dec_ops_since_last,raw_enc_ops_cumulative,raw_dec_ops_cumulative,z_enc_ops_cumulative,z_dec_ops_cumulative,raw_enc_ops_per_sec_since_last,raw_dec_ops_per_sec_since_last,z_enc_ops_per_sec_since_last,z_dec_ops_per_sec_since_last,raw_enc_ops_per_sec_cumulative,raw_dec_ops_per_sec_cumulative,z_enc_ops_per_sec_cumulative,z_dec_ops_per_sec_cumulative,total_memory_bytes")
  end

  defp print_csv_row(snapshot) do
    IO.puts("#{snapshot.elapsed_seconds},#{snapshot.raw_enc_ops_since_last},#{snapshot.raw_dec_ops_since_last},#{snapshot.z_enc_ops_since_last},#{snapshot.z_dec_ops_since_last},#{snapshot.raw_enc_ops_cumulative},#{snapshot.raw_dec_ops_cumulative},#{snapshot.z_enc_ops_cumulative},#{snapshot.z_dec_ops_cumulative},#{snapshot.raw_enc_ops_per_sec_since_last},#{snapshot.raw_dec_ops_per_sec_since_last},#{snapshot.z_enc_ops_per_sec_since_last},#{snapshot.z_dec_ops_per_sec_since_last},#{snapshot.raw_enc_ops_per_sec_cumulative},#{snapshot.raw_dec_ops_per_sec_cumulative},#{snapshot.z_enc_ops_per_sec_cumulative},#{snapshot.z_dec_ops_per_sec_cumulative},#{snapshot.total_memory_bytes}")
  end
end

# Run the benchmark
FiveMinuteBenchmark.run()
