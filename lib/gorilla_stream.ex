defmodule GorillaStream do
  @moduledoc """
  GorillaStream - High-performance time series compression using the Gorilla algorithm.

  This library provides lossless compression for time series data using Facebook's
  Gorilla compression algorithm, optimized for time-stamped floating-point data.

  ## Quick Start

      # Sample time series data: {timestamp, value} tuples
      data = [
        {1609459200, 23.5},
        {1609459260, 23.7},
        {1609459320, 23.4}
      ]

      # Compress the data
      {:ok, compressed} = GorillaStream.compress(data)

      # Decompress back to original
      {:ok, decompressed} = GorillaStream.decompress(compressed)

  ## Key Features

  - **Lossless Compression**: Perfect reconstruction of original data
  - **High Performance**: 1.7M+ points/sec encoding, up to 2M points/sec decoding
  - **Excellent Compression Ratios**: 2-42x compression depending on data patterns
  - **Production Ready**: Comprehensive error handling and validation
  - **Memory Efficient**: ~117 bytes/point memory usage for large datasets

  ## Main Functions

  The primary compression functions are provided by `GorillaStream.Compression.Gorilla`:

  - `GorillaStream.Compression.Gorilla.compress/2` - Compress time series data
  - `GorillaStream.Compression.Gorilla.decompress/2` - Decompress data

  For convenience, this module also provides direct access to these functions.
  """

  alias GorillaStream.Compression.Gorilla

  @doc """
  Compresses time series data using the Gorilla algorithm.

  This is a convenience function that delegates to `GorillaStream.Compression.Gorilla.compress/2`.

  ## Parameters
  - `data` - List of `{timestamp, value}` tuples
  - `zlib_compression?` - Optional boolean to enable additional zlib compression (default: false)

  ## Returns
  - `{:ok, compressed_binary}` - Success with compressed data
  - `{:error, reason}` - Error with description

  ## Examples

      iex> data = [{1609459200, 23.5}, {1609459201, 23.7}]
      iex> {:ok, compressed} = GorillaStream.compress(data)
      iex> is_binary(compressed)
      true

  """
  def compress(data, zlib_compression? \\ false) do
    Gorilla.compress(data, zlib_compression?)
  end

  @doc """
  Decompresses Gorilla-compressed data back to original format.

  This is a convenience function that delegates to `GorillaStream.Compression.Gorilla.decompress/2`.

  ## Parameters
  - `compressed_data` - Binary data from compress/2
  - `zlib_compression?` - Boolean indicating if zlib compression was used (default: false)

  ## Returns
  - `{:ok, decompressed_data}` - List of `{timestamp, value}` tuples
  - `{:error, reason}` - Error with description

  ## Examples

      iex> data = [{1609459200, 23.5}, {1609459201, 23.7}]
      iex> {:ok, compressed} = GorillaStream.compress(data)
      iex> {:ok, decompressed} = GorillaStream.decompress(compressed)
      iex> decompressed == data
      true

  """
  def decompress(compressed_data, zlib_compression? \\ false) do
    Gorilla.decompress(compressed_data, zlib_compression?)
  end

  @doc """
  Hello world example function.

  ## Examples

      iex> GorillaStream.hello()
      :world

  """
  def hello do
    :world
  end
end
