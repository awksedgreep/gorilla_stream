defmodule GorillaStream.Stream do
  @moduledoc """
  Streaming compression for very large datasets that don't fit in memory.

  This module provides functions to compress/decompress data in chunks,
  useful for processing massive time series datasets efficiently.

  ## Memory Efficiency

  The default chunk size is 5,000 points (~78KB memory) which provides the
  optimal balance between compression ratio and memory usage. Each chunk is
  compressed independently, allowing true streaming with constant memory overhead.

  ## Container Compression

  Supports optional container compression (zlib/zstd) via the `:compression` option:

  - `:none` - No container compression (default, fastest)
  - `:zlib` - Use zlib compression
  - `:zstd` - Use zstd compression (requires ezstd package)
  - `:auto` - Use zstd if available, fall back to zlib

  ## Examples

      # Basic streaming compression
      data_stream
      |> GorillaStream.Stream.compress_stream()
      |> Enum.each(&store_chunk/1)

      # With zstd compression and smaller chunks
      data_stream
      |> GorillaStream.Stream.compress_stream(chunk_size: 500, compression: :zstd)
      |> Enum.each(&store_chunk/1)
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
  alias GorillaStream.Compression.Container

  # Default to 5,000 points per chunk - optimal balance of compression vs memory
  # At 16 bytes/point raw, this is ~78KB per chunk before compression
  # Benchmarks show diminishing returns beyond this size
  @default_chunk_size 5_000

  @doc """
  Compresses a stream of data in chunks.

  ## Options

  - `:chunk_size` - Number of points per chunk (default: #{@default_chunk_size})
  - `:compression` - Container compression (`:none`, `:zlib`, `:zstd`, `:auto`)
  - `:victoria_metrics` - Enable VictoriaMetrics preprocessing (default: true)
  - `:is_counter` - Treat data as counter (default: false)
  - `:scale_decimals` - Decimal scaling (`:auto` or integer)

  ## Examples

      iex> large_dataset
      ...> |> GorillaStream.Stream.compress_stream(chunk_size: 500, compression: :zstd)
      ...> |> Enum.to_list()
      [{:ok, compressed_chunk_1, metadata_1}, {:ok, compressed_chunk_2, metadata_2}, ...]
  """
  def compress_stream(data_stream, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    compression = Keyword.get(opts, :compression, :none)

    # Extract encoder options
    encoder_opts = Keyword.take(opts, [:victoria_metrics, :is_counter, :scale_decimals])

    data_stream
    |> Stream.chunk_every(chunk_size)
    |> Stream.map(fn chunk ->
      with {:ok, gorilla_compressed} <- Encoder.encode(chunk, encoder_opts),
           {:ok, final_compressed} <-
             Container.compress(gorilla_compressed, compression: compression) do
        metadata = %{
          original_points: length(chunk),
          gorilla_size: byte_size(gorilla_compressed),
          compressed_size: byte_size(final_compressed),
          compression: compression,
          timestamp_range: get_timestamp_range(chunk)
        }

        {:ok, final_compressed, metadata}
      end
    end)
  end

  @doc """
  Decompresses a stream of compressed chunks.

  ## Options

  - `:compression` - Container compression used (`:none`, `:zlib`, `:zstd`, `:auto`)

  ## Examples

      compressed_chunks
      |> GorillaStream.Stream.decompress_stream(compression: :zstd)
      |> Stream.flat_map(fn {:ok, points} -> points end)
      |> Enum.to_list()
  """
  def decompress_stream(compressed_stream, opts \\ []) do
    compression = Keyword.get(opts, :compression, :none)

    compressed_stream
    |> Stream.map(fn
      {:ok, compressed, metadata} ->
        # Use compression from metadata if available, otherwise from opts
        comp = Map.get(metadata, :compression, compression)
        decompress_chunk(compressed, comp)

      {:ok, compressed} ->
        decompress_chunk(compressed, compression)

      error ->
        error
    end)
  end

  defp decompress_chunk(compressed, compression) do
    with {:ok, gorilla_data} <- Container.decompress(compressed, compression: compression),
         {:ok, points} <- Decoder.decode(gorilla_data) do
      {:ok, points}
    end
  end

  @doc """
  Returns the default chunk size used for streaming.
  """
  def default_chunk_size, do: @default_chunk_size

  defp get_timestamp_range([]), do: {nil, nil}

  defp get_timestamp_range([{first_ts, _} | _] = data) do
    {last_ts, _} = List.last(data)
    {first_ts, last_ts}
  end
end
