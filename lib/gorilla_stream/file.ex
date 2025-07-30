defmodule GorillaStream.File do
  @moduledoc """
  File I/O utilities for GorillaStream compression.

  Provides convenient functions to compress data directly to/from files
  with optional metadata and validation.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  @doc """
  Compresses data and writes it to a file.

  ## Options
  - `:metadata` - Additional metadata to store with the compressed data
  - `:validate` - Whether to validate the data after compression (default: false)

  ## Examples

      iex> data = [{1609459200, 23.5}, {1609459201, 23.6}]
      iex> GorillaStream.File.compress_to_file(data, "sensor_data.gorilla")
      {:ok, %{compressed_size: 123, original_points: 2}}
  """
  def compress_to_file(data, filename, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})
    validate = Keyword.get(opts, :validate, false)

    case Encoder.encode(data) do
      {:ok, compressed} ->
        # Create file format with metadata
        file_metadata = %{
          version: "1.0",
          compressed_at: DateTime.utc_now(),
          original_points: length(data),
          user_metadata: metadata
        }

        file_content = :erlang.term_to_binary({file_metadata, compressed})

        case File.write(filename, file_content) do
          :ok ->
            result = %{
              compressed_size: byte_size(compressed),
              file_size: byte_size(file_content),
              original_points: length(data)
            }

            if validate do
              case validate_file(filename) do
                :ok -> {:ok, result}
                error -> error
              end
            else
              {:ok, result}
            end

          {:error, reason} ->
            {:error, "File write failed: #{reason}"}
        end

      error ->
        error
    end
  end

  @doc """
  Reads and decompresses data from a file.

  ## Examples

      iex> GorillaStream.File.decompress_from_file("sensor_data.gorilla")
      {:ok, data, metadata}
  """
  def decompress_from_file(filename) do
    case File.read(filename) do
      {:ok, file_content} ->
        try do
          {file_metadata, compressed} = :erlang.binary_to_term(file_content)

          case Decoder.decode(compressed) do
            {:ok, data} ->
              {:ok, data, file_metadata}

            error ->
              error
          end
        rescue
          _ -> {:error, "Invalid file format"}
        end

      {:error, reason} ->
        {:error, "File read failed: #{reason}"}
    end
  end

  @doc """
  Validates a compressed file without fully decompressing it.
  """
  def validate_file(filename) do
    case File.read(filename) do
      {:ok, file_content} ->
        try do
          {_file_metadata, compressed} = :erlang.binary_to_term(file_content)

          case Decoder.get_compression_info(compressed) do
            {:ok, _info} -> :ok
            error -> error
          end
        rescue
          _ -> {:error, "Invalid file format"}
        end

      {:error, reason} ->
        {:error, "File read failed: #{reason}"}
    end
  end

  @doc """
  Gets information about a compressed file without decompressing.
  """
  def get_file_info(filename) do
    case File.read(filename) do
      {:ok, file_content} ->
        try do
          {file_metadata, compressed} = :erlang.binary_to_term(file_content)

          case Decoder.get_compression_info(compressed) do
            {:ok, compression_info} ->
              info =
                Map.merge(file_metadata, %{
                  file_size: byte_size(file_content),
                  compressed_size: byte_size(compressed),
                  compression_info: compression_info
                })

              {:ok, info}

            error ->
              error
          end
        rescue
          _ -> {:error, "Invalid file format"}
        end

      {:error, reason} ->
        {:error, "File read failed: #{reason}"}
    end
  end
end
