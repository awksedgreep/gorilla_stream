defmodule GorillaStream.Stream do
  @moduledoc """
  Streaming compression for very large datasets that don't fit in memory.

  This module provides functions to compress/decompress data in chunks,
  useful for processing massive time series datasets efficiently.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  @doc """
  Compresses a stream of data in chunks.

  ## Examples

      iex> large_dataset |> Stream.chunk_every(10_000) |> GorillaStream.Stream.compress_stream()
      [
        {:ok, compressed_chunk_1},
        {:ok, compressed_chunk_2},
        ...
      ]
  """
  def compress_stream(data_stream, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 10_000)

    data_stream
    |> Stream.chunk_every(chunk_size)
    |> Stream.map(fn chunk ->
      case Encoder.encode(chunk) do
        {:ok, compressed} ->
          # Optional: Add chunk metadata
          metadata = %{
            original_points: length(chunk),
            compressed_size: byte_size(compressed),
            timestamp_range: get_timestamp_range(chunk)
          }

          {:ok, compressed, metadata}

        error ->
          error
      end
    end)
  end

  @doc """
  Decompresses a stream of compressed chunks.
  """
  def decompress_stream(compressed_stream) do
    compressed_stream
    |> Stream.map(fn
      {:ok, compressed, _metadata} -> Decoder.decode(compressed)
      {:ok, compressed} -> Decoder.decode(compressed)
      error -> error
    end)
  end

  defp get_timestamp_range([]), do: {nil, nil}

  defp get_timestamp_range([{first_ts, _} | _] = data) do
    {last_ts, _} = List.last(data)
    {first_ts, last_ts}
  end
end
