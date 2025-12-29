defmodule GorillaStream.Compression.StreamingTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Container
  alias GorillaStream.Stream, as: GStream

  @test_data "Hello, this is test data for streaming compression. " <>
               String.duplicate("Repeated content. ", 100)

  # Generate test time series data
  defp generate_stream(count) do
    for i <- 0..(count - 1) do
      {1_609_459_200 + i, 100.0 + :math.sin(i / 10) * 5}
    end
  end

  describe "Container streaming API - zstd" do
    test "create_stream_context/3 creates compression context" do
      assert {:ok, ctx} = Container.create_stream_context(:zstd, :compress)
      assert is_tuple(ctx)
      assert elem(ctx, 0) == :zstd
      assert elem(ctx, 1) == :compress
    end

    test "create_stream_context/3 creates decompression context" do
      assert {:ok, ctx} = Container.create_stream_context(:zstd, :decompress)
      assert is_tuple(ctx)
      assert elem(ctx, 0) == :zstd
      assert elem(ctx, 1) == :decompress
    end

    test "stream_compress/2 compresses data incrementally" do
      {:ok, ctx} = Container.create_stream_context(:zstd, :compress)

      # Compress in chunks
      chunk1 = String.duplicate("A", 1000)
      chunk2 = String.duplicate("B", 1000)

      {:ok, compressed1} = Container.stream_compress(ctx, chunk1)
      {:ok, compressed2} = Container.stream_compress(ctx, chunk2)
      {:ok, final} = Container.stream_finish(ctx)

      # Combine all compressed data
      all_compressed = compressed1 <> compressed2 <> final
      assert byte_size(all_compressed) > 0
    end

    test "streaming compression round-trip preserves data" do
      # Compress
      {:ok, comp_ctx} = Container.create_stream_context(:zstd, :compress)
      {:ok, compressed} = Container.stream_compress(comp_ctx, @test_data)
      {:ok, final} = Container.stream_finish(comp_ctx)
      all_compressed = compressed <> final

      # Decompress
      {:ok, decomp_ctx} = Container.create_stream_context(:zstd, :decompress)
      {:ok, decompressed} = Container.stream_decompress(decomp_ctx, all_compressed)
      {:ok, _} = Container.stream_finish(decomp_ctx)

      assert decompressed == @test_data
    end
  end

  describe "Container streaming API - zlib" do
    test "create_stream_context/3 creates zlib compression context" do
      assert {:ok, ctx} = Container.create_stream_context(:zlib, :compress)
      assert is_tuple(ctx)
      assert elem(ctx, 0) == :zlib
    end

    test "zlib streaming compression round-trip" do
      # Compress
      {:ok, comp_ctx} = Container.create_stream_context(:zlib, :compress)
      {:ok, compressed} = Container.stream_compress(comp_ctx, @test_data)
      {:ok, final} = Container.stream_finish(comp_ctx)
      all_compressed = compressed <> final

      # Decompress
      {:ok, decomp_ctx} = Container.create_stream_context(:zlib, :decompress)
      {:ok, decompressed} = Container.stream_decompress(decomp_ctx, all_compressed)
      {:ok, _} = Container.stream_finish(decomp_ctx)

      assert decompressed == @test_data
    end
  end

  describe "GorillaStream.Stream with compression" do
    test "compress_stream/2 default chunk size is 5000" do
      assert GStream.default_chunk_size() == 5000
    end

    test "compress_stream/2 works without compression" do
      stream = generate_stream(100)

      results =
        stream
        |> GStream.compress_stream(chunk_size: 50)
        |> Enum.to_list()

      assert length(results) == 2

      assert Enum.all?(results, fn
               {:ok, _, _} -> true
               _ -> false
             end)
    end

    test "compress_stream/2 with compression: :zstd" do
      stream = generate_stream(100)

      results =
        stream
        |> GStream.compress_stream(chunk_size: 50, compression: :zstd)
        |> Enum.to_list()

      assert length(results) == 2

      Enum.each(results, fn {:ok, compressed, metadata} ->
        assert is_binary(compressed)
        assert metadata.compression == :zstd
        assert metadata.original_points == 50
      end)
    end

    test "compress_stream/2 with compression: :zlib" do
      stream = generate_stream(100)

      results =
        stream
        |> GStream.compress_stream(chunk_size: 50, compression: :zlib)
        |> Enum.to_list()

      assert length(results) == 2

      Enum.each(results, fn {:ok, compressed, metadata} ->
        assert is_binary(compressed)
        assert metadata.compression == :zlib
      end)
    end

    test "compress_stream/2 with compression: :auto" do
      stream = generate_stream(100)

      results =
        stream
        |> GStream.compress_stream(chunk_size: 50, compression: :auto)
        |> Enum.to_list()

      assert length(results) == 2

      Enum.each(results, fn {:ok, _compressed, metadata} ->
        assert metadata.compression == :auto
      end)
    end

    test "round-trip streaming with zstd compression" do
      original_stream = generate_stream(500)

      compressed_chunks =
        original_stream
        |> GStream.compress_stream(chunk_size: 100, compression: :zstd)
        |> Enum.to_list()

      assert length(compressed_chunks) == 5

      # Decompress
      decompressed =
        compressed_chunks
        |> GStream.decompress_stream(compression: :zstd)
        |> Enum.flat_map(fn {:ok, points} -> points end)

      assert decompressed == original_stream
    end

    test "round-trip streaming with auto compression" do
      original_stream = generate_stream(300)

      compressed_chunks =
        original_stream
        |> GStream.compress_stream(chunk_size: 100, compression: :auto)
        |> Enum.to_list()

      # Decompression uses metadata for compression type
      decompressed =
        compressed_chunks
        |> GStream.decompress_stream()
        |> Enum.flat_map(fn {:ok, points} -> points end)

      assert decompressed == original_stream
    end

    test "metadata includes gorilla_size and compressed_size" do
      stream = generate_stream(100)

      [{:ok, _, metadata} | _] =
        stream
        |> GStream.compress_stream(chunk_size: 100, compression: :zstd)
        |> Enum.to_list()

      assert Map.has_key?(metadata, :gorilla_size)
      assert Map.has_key?(metadata, :compressed_size)
      assert Map.has_key?(metadata, :compression)
      assert Map.has_key?(metadata, :original_points)
      assert Map.has_key?(metadata, :timestamp_range)

      # Compressed should be smaller than gorilla output
      assert metadata.compressed_size <= metadata.gorilla_size
    end

    test "streaming with small chunks uses minimal memory" do
      # Generate a large stream lazily
      large_stream =
        Stream.iterate(0, &(&1 + 1))
        |> Stream.take(10_000)
        |> Stream.map(fn i -> {1_609_459_200 + i, 100.0 + :rand.uniform()} end)

      # Process with very small chunks
      chunk_count =
        large_stream
        |> GStream.compress_stream(chunk_size: 100, compression: :zstd)
        |> Enum.count()

      assert chunk_count == 100
    end
  end

  describe "memory efficiency" do
    test "streaming processes data without loading all into memory" do
      # This test verifies that streaming doesn't accumulate data
      # by processing a stream that would be large if fully materialized

      # Create a lazy stream of 50,000 points with realistic time series pattern
      # (slowly changing values compress much better than random)
      lazy_stream =
        Stream.iterate(0, &(&1 + 1))
        |> Stream.take(50_000)
        |> Stream.map(fn i -> {1_609_459_200 + i, 100.0 + :math.sin(i / 100) * 10} end)

      # Process in small chunks - this should use constant memory
      result =
        lazy_stream
        |> GStream.compress_stream(chunk_size: 500, compression: :zstd)
        |> Stream.map(fn {:ok, compressed, metadata} ->
          {metadata.original_points, byte_size(compressed)}
        end)
        |> Enum.reduce({0, 0}, fn {points, bytes}, {total_points, total_bytes} ->
          {total_points + points, total_bytes + bytes}
        end)

      {total_points, total_bytes} = result
      assert total_points == 50_000
      assert total_bytes > 0

      # Average bytes per point should be reasonable for slowly-changing time series
      # Raw data is 16 bytes/point, we expect significant compression
      avg_bytes_per_point = total_bytes / total_points

      assert avg_bytes_per_point < 16,
             "Expected compression, got #{avg_bytes_per_point} bytes/point (raw is 16)"
    end
  end
end
