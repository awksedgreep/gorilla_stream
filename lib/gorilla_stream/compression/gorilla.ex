defmodule GorillaStream.Compression.Gorilla do
  @moduledoc """
  Implements Gorilla compression for time series data streams.

  This module provides compression for streams of {timestamp, number} data using
  the Gorilla compression algorithm, with optional container compression (zlib or zstd)
  for additional compression at the final step.

  ## Container Compression Options

  The `:compression` option supports:

  - `:none` - No container compression (default)
  - `:zlib` - Use zlib compression (always available, built into Erlang)
  - `:zstd` - Use zstd compression (requires ezstd package)
  - `:auto` - Use zstd if available, fall back to zlib

  For backward compatibility, the `:zlib` boolean option is still supported.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
  alias GorillaStream.Compression.Container

  @doc """
  Compresses a stream of {timestamp, number} data using the Gorilla algorithm.

  By default, VictoriaMetrics-style preprocessing is ENABLED (victoria_metrics: true),
  which applies value scaling and optional counter handling to improve compression.
  You can pass keyword options to customize or disable this behavior.

  ## Parameters
  - `stream`: An enumerable of {timestamp, number} tuples
  - Second argument may be either:
    - `zlib_compression?` (boolean) to toggle zlib container compression (default: false), OR
    - keyword options, supporting:
      - `:victoria_metrics` (boolean, default: true)
      - `:is_counter` (boolean, default: false)
      - `:scale_decimals` (:auto | integer, default: :auto)
      - `:compression` (`:none` | `:zlib` | `:zstd` | `:auto`, default: :none)
      - `:zlib` (boolean, default: false) - legacy option, use `:compression` instead

  ## Returns
  - `{:ok, compressed_data}`: When compression is successful
  - `{:error, reason}`: When compression fails

  ## Examples
      iex> stream = [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]
      iex> {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(stream, false)
      iex> is_binary(compressed)
      true

      iex> # With zlib
      iex> stream = [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]
      iex> {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(stream, true)
      iex> is_binary(compressed)
      true

      iex> # Disable VictoriaMetrics preprocessing explicitly
      iex> stream = [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]
      iex> {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(stream, victoria_metrics: false)
      iex> is_binary(compressed)
      true

      iex> # Enable counters and custom scaling via opts
      iex> stream = [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]
      iex> {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(stream, victoria_metrics: true, is_counter: true, scale_decimals: :auto)
      iex> is_binary(compressed)
      true
  """
  def compress(stream, opts_or_flag \\ false)
  def compress(stream, zlib_compression?) when is_boolean(zlib_compression?) do
    case Enum.to_list(stream) do
      [] ->
        {:ok, <<>>}

      data ->
        # Validate input stream
        case validate_stream(data) do
          :ok ->
            # Compress the data
            with {:ok, encoded_data} <- Encoder.encode(data, victoria_metrics: true, is_counter: false, scale_decimals: :auto),
                 {:ok, compressed_data} <- apply_zlib_compression(encoded_data, zlib_compression?) do
              {:ok, compressed_data}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def compress(stream, opts) when is_list(opts) do
    case Enum.to_list(stream) do
      [] ->
        {:ok, <<>>}

      data ->
        case validate_stream(data) do
          :ok ->
            with {:ok, encoded_data} <- Encoder.encode(data, opts),
                 {:ok, out} <- apply_container_compression(encoded_data, opts) do
              {:ok, out}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Decompresses previously compressed data back into the original stream of
  {timestamp, float} tuples.

  ## Parameters
  - `compressed_data`: The compressed data (binary)
  - Second argument may be either:
    - `zlib_compression?` (boolean) indicating if zlib was used (default: false), OR
    - keyword options, supporting:
      - `:compression` (`:none` | `:zlib` | `:zstd` | `:auto`, default: :none)
      - `:zlib` (boolean, default: false) - legacy option, use `:compression` instead
      - Other VM options are read from the header automatically by the decoder.

  ## Returns
  - `{:ok, original_stream}`: When decompression is successful
  - `{:error, reason}`: When decompression fails

  ## Examples
      iex> stream = [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]
      iex> {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(stream, false)
      iex> GorillaStream.Compression.Gorilla.decompress(compressed, false)
      {:ok, [{1609459200, 1.23}, {1609459201, 1.24}, {1609459202, 1.25}]}
  """
  def decompress(compressed_data, opts_or_flag \\ false)
  def decompress(compressed_data, zlib_compression?) when is_boolean(zlib_compression?) do
    case decompress_with_zlib(compressed_data, zlib_compression?) do
      {:ok, encoded_data} ->
        case Decoder.decode(encoded_data) do
          {:ok, original_stream} ->
            {:ok, original_stream}

          {:error, reason} ->
            {:error, "Decompression failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Zlib decompression failed: #{inspect(reason)}"}
    end
  end

  def decompress(compressed_data, opts) when is_list(opts) do
    case decompress_with_container(compressed_data, opts) do
      {:ok, encoded_data} ->
        case Decoder.decode(encoded_data) do
          {:ok, original_stream} -> {:ok, original_stream}
          {:error, reason} -> {:error, "Decompression failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates that a stream of data is in the correct format for compression.

  ## Parameters
  - `stream`: The stream to validate

  ## Returns
  - `:ok` if the stream is valid
  - `{:error, reason}` if the stream is invalid

  ## Examples
      iex> GorillaStream.Compression.Gorilla.validate_stream([{1609459200, 1.23}, {1609459201, 1.24}])
      :ok

      iex> GorillaStream.Compression.Gorilla.validate_stream([{1609459200, "invalid"}])
      {:error, "Invalid data format: expected {timestamp, number} tuple"}
  """
  def validate_stream(stream) do
    case Enum.all?(stream, &is_valid_data_tuple?/1) do
      true -> :ok
      false -> {:error, "Invalid data format: expected {timestamp, number} tuple"}
    end
  end

  # Private functions

  defp is_valid_data_tuple?({timestamp, value})
       when is_integer(timestamp) and (is_float(value) or is_integer(value)) do
    true
  end

  defp is_valid_data_tuple?(_) do
    false
  end

  defp apply_zlib_compression(data, true) do
    try do
      compressed = :zlib.compress(data)
      {:ok, compressed}
    rescue
      error ->
        {:error, "Zlib compression failed: #{inspect(error)}"}
    end
  end

  defp apply_zlib_compression(data, false) do
    {:ok, data}
  end

  defp decompress_with_zlib(compressed_data, true) do
    try do
      decompressed = :zlib.uncompress(compressed_data)
      {:ok, decompressed}
    rescue
      error ->
        {:error, "Zlib decompression failed: #{inspect(error)}"}
    end
  end

  defp decompress_with_zlib(data, false) do
    {:ok, data}
  end

  # Container compression using the Container module (supports zlib, zstd, auto)
  defp apply_container_compression(data, opts) when is_list(opts) do
    Container.compress(data, opts)
  end

  defp decompress_with_container(data, opts) when is_list(opts) do
    Container.decompress(data, opts)
  end
end

# The implementation includes:

# 1. A main module `GorillaStream.Compression.Gorilla` that provides compression and decompression functions
# 2. Support for streams of `{timestamp, float}` data
# 3. Optional Zlib compression at the final step
# 4. Proper error handling with descriptive error messages
# 5. Comprehensive documentation with examples
# 6. Input validation to ensure data is in the correct format
# 7. Separation of concerns with dedicated Encoder and Decoder modules

# The implementation follows Elixir best practices with proper error handling, clear documentation, and a clean interface. The Zlib compression is optional and can be enabled via the `zlib_compression?` flag.

# I've structured the module to be easy to use while providing the necessary flexibility for different use cases. The compression algorithm will be most effective for time series data with small timestamp deltas and slowly changing values, which is common in many real-world scenarios.
