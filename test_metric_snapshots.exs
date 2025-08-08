#!/usr/bin/env elixir

# Test script for MetricSnapshots module
# Usage: mix run test_metric_snapshots.exs

defmodule TestMetricSnapshots do
  @moduledoc """
  Test script to verify the MetricSnapshots module works correctly.
  Runs for 35 seconds to capture at least 3 snapshots.
  """

  alias GorillaStream.Performance.MetricSnapshots

  def run() do
    IO.puts("Starting MetricSnapshots test...")
    IO.puts("This will run for 35 seconds to capture multiple snapshots")
    IO.puts("=" |> String.duplicate(60))

    # Start the metric snapshot system
    {:ok, _pid} = MetricSnapshots.start_link()

    # Simulate some work with increasing operation counts
    simulate_work(35_000)  # 35 seconds

    # Stop and get snapshots
    snapshots = MetricSnapshots.stop_and_get_snapshots()

    # Display results
    display_test_results(snapshots)
  end

  defp simulate_work(duration_ms) do
    start_time = System.monotonic_time(:millisecond)
    deadline = start_time + duration_ms
    simulate_work_loop(deadline, start_time, %{raw_enc_ops: 0, raw_dec_ops: 0, z_enc_ops: 0, z_dec_ops: 0})
  end

  defp simulate_work_loop(deadline, start_time, ops) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time >= deadline do
      :ok
    else
      # Simulate some work (sleep briefly)
      :timer.sleep(100)  # 100ms
      
      # Increment operation counters
      new_ops = %{
        raw_enc_ops: ops.raw_enc_ops + 2,  # 2 ops per 100ms = 20 ops/sec
        raw_dec_ops: ops.raw_dec_ops + 2,
        z_enc_ops: ops.z_enc_ops + 1,     # 1 op per 100ms = 10 ops/sec  
        z_dec_ops: ops.z_dec_ops + 1
      }

      # Update metrics
      MetricSnapshots.update_ops_counters(new_ops)

      # Show progress every 5 seconds
      elapsed = current_time - start_time
      if rem(div(elapsed, 1000), 5) == 0 and rem(elapsed, 5000) < 100 do
        IO.puts("Test progress: #{div(elapsed, 1000)}s elapsed (Raw: #{new_ops.raw_enc_ops}/#{new_ops.raw_dec_ops}, Zlib: #{new_ops.z_enc_ops}/#{new_ops.z_dec_ops})")
      end

      simulate_work_loop(deadline, start_time, new_ops)
    end
  end

  defp display_test_results(snapshots) do
    IO.puts("\n" <> ("=" |> String.duplicate(60)))
    IO.puts("METRIC SNAPSHOTS TEST RESULTS")
    IO.puts("=" |> String.duplicate(60))
    
    IO.puts("Total snapshots captured: #{length(snapshots)}")
    
    if length(snapshots) > 0 do
      first_snapshot = List.first(snapshots)
      last_snapshot = List.last(snapshots)
      
      IO.puts("First snapshot at: #{first_snapshot.elapsed_seconds}s")
      IO.puts("Last snapshot at: #{last_snapshot.elapsed_seconds}s")
      IO.puts("Final memory: #{format_bytes(last_snapshot.total_memory_bytes)}")
      IO.puts("")
      
      IO.puts("FINAL CUMULATIVE RATES:")
      IO.puts("  Raw Encode: #{last_snapshot.raw_enc_ops_per_sec_cumulative} ops/sec")
      IO.puts("  Raw Decode: #{last_snapshot.raw_dec_ops_per_sec_cumulative} ops/sec") 
      IO.puts("  Zlib Encode: #{last_snapshot.z_enc_ops_per_sec_cumulative} ops/sec")
      IO.puts("  Zlib Decode: #{last_snapshot.z_dec_ops_per_sec_cumulative} ops/sec")
    end
    
    IO.puts("")
    IO.puts("CSV OUTPUT:")
    IO.puts("=" |> String.duplicate(60))
    MetricSnapshots.print_csv_report()
    
    IO.puts("")
    IO.puts("Test completed successfully!")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end

# Run the test
TestMetricSnapshots.run()
