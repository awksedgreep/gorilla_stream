#!/usr/bin/env elixir

# 5 Million Data Point Benchmark for Gorilla compression
# Usage: mix run five_million_benchmark.exs

defmodule FiveMillionBenchmark do
  @moduledoc """
  Benchmark script for 5 million data points testing raw Gorilla and zlib variants.
  Tests four categories: raw_enc, raw_dec, z_enc, z_dec
  Measures ops/sec and validates against performance floors.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  def run() do
    IO.puts("Starting 5 Million Data Point Benchmark...")
    IO.puts("Testing: raw_enc, raw_dec, z_enc, z_dec")
    IO.puts("Expected floors: raw_enc ≥ 1,000,000, raw_dec ≥ 1,500,000, z_enc ≥ 750,000, z_dec ≥ 1,000,000")
    IO.puts("=" |> String.duplicate(80))

    # Generate 5 million data points
    IO.puts("Generating 5 million data points...")
    dataset = generate_dataset(5_000_000)
    IO.puts("Dataset generated with #{length(dataset)} points")
    
    IO.puts("\nRunning benchmark operations...")
    
    # Test raw Gorilla encoding
    IO.puts("Testing raw Gorilla encoding...")
    {raw_enc_time, {:ok, raw_compressed}} = :timer.tc(fn -> 
      Encoder.encode(dataset) 
    end)
    raw_enc_ops_per_sec = trunc(length(dataset) / (raw_enc_time / 1_000_000))
    IO.puts("Raw encoding: #{raw_enc_time / 1_000_000} seconds, #{raw_enc_ops_per_sec} ops/sec")
    
    # Test raw Gorilla decoding
    IO.puts("Testing raw Gorilla decoding...")
    {raw_dec_time, {:ok, _raw_decompressed}} = :timer.tc(fn -> 
      Decoder.decode(raw_compressed) 
    end)
    raw_dec_ops_per_sec = trunc(length(dataset) / (raw_dec_time / 1_000_000))
    IO.puts("Raw decoding: #{raw_dec_time / 1_000_000} seconds, #{raw_dec_ops_per_sec} ops/sec")
    
    # Test zlib-enabled Gorilla encoding
    IO.puts("Testing zlib-enabled Gorilla encoding...")
    {z_enc_time, {:ok, z_compressed}} = :timer.tc(fn ->
      GorillaStream.compress(dataset, true)
    end)
    z_enc_ops_per_sec = trunc(length(dataset) / (z_enc_time / 1_000_000))
    IO.puts("Zlib encoding: #{z_enc_time / 1_000_000} seconds, #{z_enc_ops_per_sec} ops/sec")
    
    # Test zlib-enabled Gorilla decoding
    IO.puts("Testing zlib-enabled Gorilla decoding...")
    {z_dec_time, {:ok, _z_decompressed}} = :timer.tc(fn ->
      GorillaStream.decompress(z_compressed, true)
    end)
    z_dec_ops_per_sec = trunc(length(dataset) / (z_dec_time / 1_000_000))
    IO.puts("Zlib decoding: #{z_dec_time / 1_000_000} seconds, #{z_dec_ops_per_sec} ops/sec")
    
    # Display results
    display_results(%{
      raw_enc: raw_enc_ops_per_sec,
      raw_dec: raw_dec_ops_per_sec,
      z_enc: z_enc_ops_per_sec,
      z_dec: z_dec_ops_per_sec
    })
  end

  defp generate_dataset(size) do
    IO.puts("Generating #{size} data points...")
    base_timestamp = 1_609_459_200
    
    # Generate realistic time series data
    for i <- 0..(size - 1) do
      # Simulate sensor readings with variations
      base_value = 100.0
      variation = :math.sin(i * 0.001) * 10.0  # Slower sine wave for 5M points
      noise = (:rand.uniform() - 0.5) * 2.0   # Random noise
      value = base_value + variation + noise
      
      {base_timestamp + i * 60, value}  # Every minute
    end
  end

  defp display_results(results) do
    IO.puts("\n" <> ("=" |> String.duplicate(80)))
    IO.puts("5 MILLION DATA POINT BENCHMARK RESULTS")
    IO.puts("=" |> String.duplicate(80))
    
    IO.puts("FINAL KPIs:")
    IO.puts("  raw_enc ops/sec: #{results.raw_enc}")
    IO.puts("  raw_dec ops/sec: #{results.raw_dec}")
    IO.puts("  z_enc ops/sec:   #{results.z_enc}")
    IO.puts("  z_dec ops/sec:   #{results.z_dec}")
    IO.puts("")
    
    # Expected floors with 15% grace
    expected_floors = %{
      raw_enc: 1_000_000,
      raw_dec: 1_500_000,
      z_enc: 750_000,
      z_dec: 1_000_000
    }
    
    grace_multiplier = 0.85  # 15% grace = 85% of expected
    
    # Performance validation
    IO.puts("REGRESSION ANALYSIS (with 15% grace):")
    
    floors = %{
      raw_enc: trunc(expected_floors.raw_enc * grace_multiplier),
      raw_dec: trunc(expected_floors.raw_dec * grace_multiplier),
      z_enc: trunc(expected_floors.z_enc * grace_multiplier),
      z_dec: trunc(expected_floors.z_dec * grace_multiplier)
    }
    
    IO.puts("")    
    IO.puts("| Category | Ops/Sec  | Floor     | Status |")
    IO.puts("|----------|----------|-----------|--------|")  
    
    regression_results = 
      for {category, actual} <- results do
        floor = floors[category]
        status = if actual >= floor, do: "PASS", else: "FAIL"
        passed = actual >= floor
        
        IO.puts("| #{String.pad_trailing("#{category}", 8)} | #{String.pad_leading("#{actual}", 8)} | #{String.pad_leading("#{floor}", 9)} | #{status}   |")
        
        passed
      end
    
    IO.puts("")
    
    # Check if all tests passed
    all_passed = Enum.all?(regression_results)
    
    if not all_passed do
      IO.puts("❌ REGRESSION DETECTED! Some operations failed to meet performance floors.")
      System.halt(1)
    else
      IO.puts("✅ ALL PERFORMANCE CHECKS PASSED!")
    end
    
    IO.puts("")
    IO.puts("Benchmark completed successfully!")
  end
end

# Run the benchmark
FiveMillionBenchmark.run()
