defmodule GorillaStream.Compression.Container do
  @moduledoc """
  Container compression utilities for GorillaStream.

  Provides a unified interface for applying secondary compression (zlib or zstd)
  on top of Gorilla-compressed data. Zstd is preferred when available as it
  typically achieves better compression ratios and faster speeds than zlib.

  ## Compression Options

  The `:compression` option accepts the following values:

  - `:none` - No container compression (default)
  - `:zlib` - Use zlib compression (always available, built into Erlang)
  - `:zstd` - Use zstd compression (requires ezstd package)
  - `:auto` - Use zstd if available, fall back to zlib

  ## Examples

      # No compression (default)
      {:ok, data} = Container.compress(binary, compression: :none)

      # Use zlib
      {:ok, data} = Container.compress(binary, compression: :zlib)

      # Use zstd (requires ezstd)
      {:ok, data} = Container.compress(binary, compression: :zstd)

      # Auto-select best available
      {:ok, data} = Container.compress(binary, compression: :auto)

  ## Streaming Compression

  For continuous streaming with minimal memory overhead, use the streaming API:

      # Create a streaming context
      {:ok, ctx} = Container.create_stream_context(:zstd, :compress)

      # Compress chunks as they arrive
      {:ok, compressed1} = Container.stream_compress(ctx, chunk1)
      {:ok, compressed2} = Container.stream_compress(ctx, chunk2)

      # Finalize the stream
      {:ok, final} = Container.stream_finish(ctx)

  ## Legacy Support

  For backward compatibility, the `:zlib` boolean option is still supported:

      {:ok, data} = Container.compress(binary, zlib: true)  # Same as compression: :zlib
  """

  # Default buffer size for streaming contexts (64KB)
  @default_stream_buffer_size 65_536

  @type compression_type :: :none | :zlib | :zstd | :auto

  @doc """
  Checks if the ezstd library is available at runtime.

  ## Examples

      iex> GorillaStream.Compression.Container.zstd_available?()
      true  # or false, depending on whether ezstd is installed
  """
  @spec zstd_available?() :: boolean()
  def zstd_available? do
    Code.ensure_loaded?(:ezstd)
  end

  @doc """
  Compresses data using the specified compression algorithm.

  ## Parameters

  - `data` - Binary data to compress
  - `opts` - Keyword list of options:
    - `:compression` - Compression type (`:none`, `:zlib`, `:zstd`, `:auto`)
    - `:zlib` - Legacy boolean option for zlib compression

  ## Returns

  - `{:ok, compressed_data}` on success
  - `{:error, reason}` on failure
  """
  @spec compress(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def compress(data, opts \\ []) when is_binary(data) do
    compression_type = resolve_compression_type(opts)
    do_compress(data, compression_type)
  end

  @doc """
  Decompresses data using the specified compression algorithm.

  ## Parameters

  - `data` - Binary data to decompress
  - `opts` - Keyword list of options:
    - `:compression` - Compression type (`:none`, `:zlib`, `:zstd`, `:auto`)
    - `:zlib` - Legacy boolean option for zlib compression

  ## Returns

  - `{:ok, decompressed_data}` on success
  - `{:error, reason}` on failure
  """
  @spec decompress(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def decompress(data, opts \\ []) when is_binary(data) do
    compression_type = resolve_compression_type(opts)
    do_decompress(data, compression_type)
  end

  @doc """
  Returns the actual compression algorithm that will be used for the given options.

  Useful for debugging or understanding what compression will be applied.

  ## Examples

      iex> GorillaStream.Compression.Container.effective_compression(compression: :auto)
      :zstd  # or :zlib if ezstd not available
  """
  @spec effective_compression(keyword()) :: compression_type()
  def effective_compression(opts) do
    case resolve_compression_type(opts) do
      :auto -> if zstd_available?(), do: :zstd, else: :zlib
      other -> other
    end
  end

  # Private functions

  defp resolve_compression_type(opts) do
    cond do
      # New style: compression: :zstd/:zlib/:auto/:none
      compression = Keyword.get(opts, :compression) ->
        compression

      # Legacy style: zlib: true/false
      Keyword.get(opts, :zlib, false) ->
        :zlib

      true ->
        :none
    end
  end

  defp do_compress(data, :none), do: {:ok, data}

  defp do_compress(data, :zlib) do
    try do
      compressed = :zlib.compress(data)
      {:ok, compressed}
    rescue
      error ->
        {:error, "Zlib compression failed: #{inspect(error)}"}
    end
  end

  defp do_compress(data, :zstd) do
    if zstd_available?() do
      # Handle empty binary specially - zstd doesn't handle it well
      if data == <<>> do
        {:ok, <<>>}
      else
        try do
          case :ezstd.compress(data) do
            {:error, reason} -> {:error, "Zstd compression failed: #{reason}"}
            compressed when is_binary(compressed) -> {:ok, compressed}
          end
        rescue
          error ->
            {:error, "Zstd compression failed: #{inspect(error)}"}
        end
      end
    else
      {:error,
       "Zstd compression requested but ezstd is not installed. Add {:ezstd, \"~> 1.2\"} to your dependencies."}
    end
  end

  defp do_compress(data, :auto) do
    if zstd_available?() do
      do_compress(data, :zstd)
    else
      do_compress(data, :zlib)
    end
  end

  defp do_decompress(data, :none), do: {:ok, data}

  defp do_decompress(data, :zlib) do
    try do
      decompressed = :zlib.uncompress(data)
      {:ok, decompressed}
    rescue
      error ->
        {:error, "Zlib decompression failed: #{inspect(error)}"}
    end
  end

  defp do_decompress(data, :zstd) do
    if zstd_available?() do
      # Handle empty binary specially
      if data == <<>> do
        {:ok, <<>>}
      else
        try do
          case :ezstd.decompress(data) do
            {:error, reason} -> {:error, "Zstd decompression failed: #{reason}"}
            decompressed when is_binary(decompressed) -> {:ok, decompressed}
          end
        rescue
          error ->
            {:error, "Zstd decompression failed: #{inspect(error)}"}
        end
      end
    else
      {:error,
       "Zstd decompression requested but ezstd is not installed. Add {:ezstd, \"~> 1.2\"} to your dependencies."}
    end
  end

  defp do_decompress(data, :auto) do
    if zstd_available?() do
      do_decompress(data, :zstd)
    else
      do_decompress(data, :zlib)
    end
  end

  # =============================================================================
  # Streaming Compression API
  # =============================================================================

  @doc """
  Creates a streaming compression or decompression context.

  Streaming contexts allow compressing/decompressing data incrementally
  with minimal memory overhead - ideal for continuous data streams.

  ## Parameters

  - `type` - `:zstd` or `:zlib`
  - `mode` - `:compress` or `:decompress`
  - `opts` - Options:
    - `:buffer_size` - Buffer size in bytes (default: 64KB)

  ## Returns

  - `{:ok, context}` - A streaming context
  - `{:error, reason}` - If the compression type is not available

  ## Examples

      {:ok, ctx} = Container.create_stream_context(:zstd, :compress)
  """
  @spec create_stream_context(:zstd | :zlib, :compress | :decompress, keyword()) ::
          {:ok, term()} | {:error, String.t()}
  def create_stream_context(type, mode, opts \\ [])

  def create_stream_context(:zstd, :compress, opts) do
    if zstd_available?() do
      buffer_size = Keyword.get(opts, :buffer_size, @default_stream_buffer_size)

      case :ezstd.create_compression_context(buffer_size) do
        {:error, reason} -> {:error, "Failed to create zstd compression context: #{reason}"}
        ctx when is_reference(ctx) -> {:ok, {:zstd, :compress, ctx}}
      end
    else
      {:error, "Zstd not available. Add {:ezstd, \"~> 1.2\"} to your dependencies."}
    end
  end

  def create_stream_context(:zstd, :decompress, opts) do
    if zstd_available?() do
      buffer_size = Keyword.get(opts, :buffer_size, @default_stream_buffer_size)

      case :ezstd.create_decompression_context(buffer_size) do
        {:error, reason} -> {:error, "Failed to create zstd decompression context: #{reason}"}
        ctx when is_reference(ctx) -> {:ok, {:zstd, :decompress, ctx}}
      end
    else
      {:error, "Zstd not available. Add {:ezstd, \"~> 1.2\"} to your dependencies."}
    end
  end

  def create_stream_context(:zlib, :compress, _opts) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z)
    {:ok, {:zlib, :compress, z}}
  end

  def create_stream_context(:zlib, :decompress, _opts) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z)
    {:ok, {:zlib, :decompress, z}}
  end

  @doc """
  Compresses data using a streaming context.

  Data is compressed incrementally. Call `stream_finish/1` when done.

  ## Returns

  - `{:ok, compressed_data}` - Compressed output (may be empty if buffered)
  - `{:error, reason}` - On failure
  """
  @spec stream_compress(term(), binary()) :: {:ok, binary()} | {:error, String.t()}
  def stream_compress({:zstd, :compress, ctx}, data) when is_binary(data) do
    try do
      case :ezstd.compress_streaming(ctx, data) do
        {:error, reason} -> {:error, "Zstd streaming compression failed: #{reason}"}
        iolist -> {:ok, IO.iodata_to_binary(iolist)}
      end
    rescue
      error -> {:error, "Zstd streaming compression failed: #{inspect(error)}"}
    end
  end

  def stream_compress({:zlib, :compress, z}, data) when is_binary(data) do
    try do
      compressed = :zlib.deflate(z, data, :sync)
      {:ok, IO.iodata_to_binary(compressed)}
    rescue
      error -> {:error, "Zlib streaming compression failed: #{inspect(error)}"}
    end
  end

  @doc """
  Decompresses data using a streaming context.

  ## Returns

  - `{:ok, decompressed_data}` - Decompressed output
  - `{:error, reason}` - On failure
  """
  @spec stream_decompress(term(), binary()) :: {:ok, binary()} | {:error, String.t()}
  def stream_decompress({:zstd, :decompress, ctx}, data) when is_binary(data) do
    try do
      case :ezstd.decompress_streaming(ctx, data) do
        {:error, reason} -> {:error, "Zstd streaming decompression failed: #{reason}"}
        iolist -> {:ok, IO.iodata_to_binary(iolist)}
      end
    rescue
      error -> {:error, "Zstd streaming decompression failed: #{inspect(error)}"}
    end
  end

  def stream_decompress({:zlib, :decompress, z}, data) when is_binary(data) do
    try do
      decompressed = :zlib.inflate(z, data)
      {:ok, IO.iodata_to_binary(decompressed)}
    rescue
      error -> {:error, "Zlib streaming decompression failed: #{inspect(error)}"}
    end
  end

  @doc """
  Finishes a streaming compression context and returns any remaining data.

  For compression, this flushes the final compressed bytes.
  For decompression, this verifies the stream is complete.

  After calling this, the context should not be used again.

  ## Returns

  - `{:ok, final_data}` - Any remaining compressed/decompressed data
  - `{:error, reason}` - On failure
  """
  @spec stream_finish(term()) :: {:ok, binary()} | {:error, String.t()}
  def stream_finish({:zstd, :compress, ctx}) do
    try do
      case :ezstd.compress_streaming_end(ctx, <<>>) do
        {:error, reason} -> {:error, "Zstd stream finish failed: #{reason}"}
        iolist -> {:ok, IO.iodata_to_binary(iolist)}
      end
    rescue
      error -> {:error, "Zstd stream finish failed: #{inspect(error)}"}
    end
  end

  def stream_finish({:zstd, :decompress, _ctx}) do
    # Decompression context doesn't need explicit finish
    {:ok, <<>>}
  end

  def stream_finish({:zlib, :compress, z}) do
    try do
      final = :zlib.deflate(z, <<>>, :finish)
      :ok = :zlib.deflateEnd(z)
      :ok = :zlib.close(z)
      {:ok, IO.iodata_to_binary(final)}
    rescue
      error -> {:error, "Zlib stream finish failed: #{inspect(error)}"}
    end
  end

  def stream_finish({:zlib, :decompress, z}) do
    try do
      :ok = :zlib.inflateEnd(z)
      :ok = :zlib.close(z)
      {:ok, <<>>}
    rescue
      error -> {:error, "Zlib stream finish failed: #{inspect(error)}"}
    end
  end
end
