#!/usr/bin/env elixir

# Usage: mix run scripts/compression_benchmark.exs
#
# Compares compression speed and ratio across all backends:
#   none, zlib, zstd, openzl

defmodule CompressionBenchmark do
  alias GorillaStream.Compression.Gorilla

  @iterations 200

  # Dataset generators
  defp datasets do
    %{
      "sine_1k" => sine_wave(1_000),
      "sine_10k" => sine_wave(10_000),
      "counter_1k" => counter(1_000),
      "counter_10k" => counter(10_000),
      "noisy_1k" => noisy(1_000),
      "noisy_10k" => noisy(10_000)
    }
  end

  defp sine_wave(n) do
    for i <- 0..(n - 1), do: {1_609_459_200 + i, 100.0 + :math.sin(i / 10) * 5}
  end

  defp counter(n) do
    for i <- 0..(n - 1), do: {1_609_459_200 + i, 1000 + i * 10}
  end

  defp noisy(n) do
    for i <- 0..(n - 1), do: {1_609_459_200 + i, :rand.uniform() * 1000}
  end

  def run do
    backends = [:none, :zlib, :zstd, :openzl]
    data = datasets()

    IO.puts("Compression Benchmark — #{@iterations} iterations per measurement")
    IO.puts(String.duplicate("=", 100))

    # Print header
    IO.puts(
      String.pad_trailing("Dataset", 14) <>
        String.pad_trailing("Backend", 10) <>
        String.pad_trailing("Raw", 10) <>
        String.pad_trailing("Compressed", 12) <>
        String.pad_trailing("Ratio", 8) <>
        String.pad_trailing("Saved", 8) <>
        String.pad_trailing("Compress", 14) <>
        String.pad_trailing("Decompress", 14) <>
        "OK?"
    )

    IO.puts(String.duplicate("-", 104))

    for {name, points} <- Enum.sort(data) do
      # Get raw (gorilla-only) size once
      {:ok, raw} = Gorilla.compress(points, compression: :none)
      raw_size = byte_size(raw)

      for backend <- backends do
        # Warm up
        {:ok, compressed} = Gorilla.compress(points, compression: backend)
        {:ok, _} = Gorilla.decompress(compressed, compression: backend)

        # Benchmark compress
        {compress_us, _} =
          :timer.tc(fn ->
            for _ <- 1..@iterations do
              {:ok, _} = Gorilla.compress(points, compression: backend)
            end
          end)

        compressed_size = byte_size(compressed)
        avg_compress_us = compress_us / @iterations

        # Benchmark decompress
        {decompress_us, _} =
          :timer.tc(fn ->
            for _ <- 1..@iterations do
              {:ok, _} = Gorilla.decompress(compressed, compression: backend)
            end
          end)

        avg_decompress_us = decompress_us / @iterations

        # Verify round-trip
        {:ok, decompressed} = Gorilla.decompress(compressed, compression: backend)
        ok? = decompressed == points

        ratio =
          if compressed_size > 0,
            do: Float.round(raw_size / compressed_size, 1),
            else: 0.0

        saved =
          if raw_size > 0,
            do: Float.round((1 - compressed_size / raw_size) * 100, 1),
            else: 0.0

        IO.puts(
          String.pad_trailing(name, 14) <>
            String.pad_trailing(to_string(backend), 10) <>
            String.pad_trailing(format_size(raw_size), 10) <>
            String.pad_trailing(format_size(compressed_size), 12) <>
            String.pad_trailing("#{ratio}x", 8) <>
            String.pad_trailing("#{saved}%", 8) <>
            String.pad_trailing("#{Float.round(avg_compress_us, 0)} us", 14) <>
            String.pad_trailing("#{Float.round(avg_decompress_us, 0)} us", 14) <>
            if(ok?, do: "OK", else: "FAIL")
        )
      end

      IO.puts("")
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end

CompressionBenchmark.run()
