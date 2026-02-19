#!/usr/bin/env elixir

# Usage: mix run scripts/container_benchmark.exs
#
# Benchmarks container compression/decompression in isolation,
# without Gorilla encode/decode overhead.

defmodule ContainerBenchmark do
  alias GorillaStream.Compression.Container

  @iterations 500

  defp datasets do
    # Pre-compress with Gorilla to get realistic binary payloads
    counter_10k = for i <- 0..9999, do: {1_609_459_200 + i, 1000 + i * 10}
    sine_10k = for i <- 0..9999, do: {1_609_459_200 + i, 100.0 + :math.sin(i / 10) * 5}
    noisy_10k = for i <- 0..9999, do: {1_609_459_200 + i, :rand.uniform() * 1000}

    %{
      "counter_10k" => gorilla_encode(counter_10k),
      "sine_10k" => gorilla_encode(sine_10k),
      "noisy_10k" => gorilla_encode(noisy_10k),
      "random_64KB" => :crypto.strong_rand_bytes(65_536),
      "zeros_64KB" => :binary.copy(<<0>>, 65_536)
    }
  end

  defp gorilla_encode(points) do
    {:ok, bin} = GorillaStream.Compression.Gorilla.compress(points, compression: :none)
    bin
  end

  def run do
    backends = [:zlib, :zstd, :openzl]
    data = datasets()

    IO.puts("Container-Only Benchmark — #{@iterations} iterations per measurement")
    IO.puts("(Gorilla encode/decode excluded — pure container compression speed)")
    IO.puts(String.duplicate("=", 110))

    IO.puts(
      String.pad_trailing("Dataset", 16) <>
        String.pad_trailing("Backend", 10) <>
        String.pad_trailing("Input", 10) <>
        String.pad_trailing("Output", 10) <>
        String.pad_trailing("Ratio", 8) <>
        String.pad_trailing("Saved", 8) <>
        String.pad_trailing("Compress", 14) <>
        String.pad_trailing("Decompress", 14) <>
        "Throughput (decomp)"
    )

    IO.puts(String.duplicate("-", 110))

    for {name, raw} <- Enum.sort(data) do
      raw_size = byte_size(raw)

      for backend <- backends do
        # Warm up
        {:ok, compressed} = Container.compress(raw, compression: backend)
        {:ok, _} = Container.decompress(compressed, compression: backend)

        # Benchmark compress
        {compress_us, _} =
          :timer.tc(fn ->
            for _ <- 1..@iterations do
              {:ok, _} = Container.compress(raw, compression: backend)
            end
          end)

        compressed_size = byte_size(compressed)
        avg_compress_us = compress_us / @iterations

        # Benchmark decompress
        {decompress_us, _} =
          :timer.tc(fn ->
            for _ <- 1..@iterations do
              {:ok, _} = Container.decompress(compressed, compression: backend)
            end
          end)

        avg_decompress_us = decompress_us / @iterations

        # Verify
        {:ok, ^raw} = Container.decompress(compressed, compression: backend)

        ratio =
          if compressed_size > 0,
            do: Float.round(raw_size / compressed_size, 1),
            else: 0.0

        saved =
          if raw_size > 0,
            do: Float.round((1 - compressed_size / raw_size) * 100, 1),
            else: 0.0

        # MB/s based on input size and decompress time
        throughput_mbps =
          if avg_decompress_us > 0,
            do: Float.round(raw_size / avg_decompress_us, 1),
            else: 0.0

        IO.puts(
          String.pad_trailing(name, 16) <>
            String.pad_trailing(to_string(backend), 10) <>
            String.pad_trailing(format_size(raw_size), 10) <>
            String.pad_trailing(format_size(compressed_size), 10) <>
            String.pad_trailing("#{ratio}x", 8) <>
            String.pad_trailing("#{saved}%", 8) <>
            String.pad_trailing("#{Float.round(avg_compress_us, 0)} us", 14) <>
            String.pad_trailing("#{Float.round(avg_decompress_us, 0)} us", 14) <>
            "#{throughput_mbps} MB/s"
        )
      end

      IO.puts("")
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end

ContainerBenchmark.run()
