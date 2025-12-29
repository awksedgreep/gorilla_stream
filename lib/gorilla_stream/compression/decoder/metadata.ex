defmodule GorillaStream.Compression.Decoder.Metadata do
  @moduledoc """
  Metadata extraction module for Gorilla compression decompression.

  This module handles the extraction and parsing of metadata headers from
  compressed data created by the Gorilla compression algorithm.

  The metadata format includes:
  - Magic number for format identification
  - Version information
  - Compression parameters
  - Data statistics
  - Checksum for integrity verification
  """

  # "GORILLA" in hex
  @magic_number 0x474F52494C4C41
  @version 1

  @doc """
  Extracts metadata from encoded data.

  ## Parameters
  - `encoded_data`: Binary data containing metadata header and compressed data

  ## Returns
  - `{metadata, remaining_data}`: Tuple containing extracted metadata and remaining data
  """
  def extract_metadata(encoded_data) when is_binary(encoded_data) do
    if byte_size(encoded_data) < 80 do
      # No metadata header found, return empty metadata
      {%{count: 0}, encoded_data}
    else
      case parse_metadata_header(encoded_data) do
        {:ok, metadata, remaining_data} ->
          # Verify checksum if data is present
          case verify_data_integrity(metadata, remaining_data) do
            :ok ->
              {metadata, remaining_data}

            {:error, _reason} ->
              # Checksum failed, but return data anyway with warning flag
              {Map.put(metadata, :checksum_failed, true), remaining_data}
          end

        {:error, _reason} ->
          # Invalid header, treat as raw data
          {%{count: 0}, encoded_data}
      end
    end
  end

  def extract_metadata(_), do: {%{count: 0}, <<>>}

  # Parse the metadata header
  # Parse v1 (80 bytes) or v2 (84 bytes) headers
  defp parse_metadata_header(<<
         @magic_number::64,
         version::16,
         header_length::16,
         count::32,
         compressed_size::32,
         original_size::32,
         checksum::32,
         first_timestamp::64,
         first_delta::32-signed,
         first_value_bits::64,
         timestamp_bit_length::32,
         value_bit_length::32,
         total_bits::32,
         compression_ratio::float-64,
         creation_time::64,
         flags::32,
         rest::binary
       >>) do
    cond do
      version <= @version and header_length == 80 and byte_size(rest) >= compressed_size ->
        parse_with_scale(
          first_timestamp,
          first_delta,
          first_value_bits,
          timestamp_bit_length,
          value_bit_length,
          total_bits,
          compression_ratio,
          creation_time,
          flags,
          0,
          rest,
          compressed_size,
          version,
          header_length,
          count,
          original_size,
          checksum
        )

      version <= @version and header_length == 84 and byte_size(rest) >= compressed_size + 4 ->
        <<scale_decimals::32, remaining_data::binary>> = rest

        parse_with_scale(
          first_timestamp,
          first_delta,
          first_value_bits,
          timestamp_bit_length,
          value_bit_length,
          total_bits,
          compression_ratio,
          creation_time,
          flags,
          scale_decimals,
          remaining_data,
          compressed_size,
          version,
          header_length,
          count,
          original_size,
          checksum
        )

      true ->
        {:error, "Invalid header format or version"}
    end
  end

  defp parse_metadata_header(_), do: {:error, "Invalid metadata header"}

  defp parse_with_scale(
         first_timestamp,
         first_delta,
         first_value_bits,
         timestamp_bit_length,
         value_bit_length,
         total_bits,
         compression_ratio,
         creation_time,
         flags,
         scale_decimals,
         data,
         compressed_size,
         version,
         header_length,
         count,
         original_size,
         checksum
       ) do
    first_value = bits_to_float(first_value_bits)

    timestamp_metadata = %{
      count: count,
      first_timestamp: first_timestamp,
      first_delta: if(count > 1, do: first_delta, else: nil)
    }

    value_metadata = %{
      count: count,
      first_value: first_value
    }

    metadata = %{
      version: version,
      header_length: header_length,
      count: count,
      compressed_size: compressed_size,
      original_size: original_size,
      checksum: checksum,
      timestamp_bit_length: timestamp_bit_length,
      value_bit_length: value_bit_length,
      total_bits: total_bits,
      compression_ratio: compression_ratio,
      creation_time: creation_time,
      flags: flags,
      scale_decimals: scale_decimals,
      timestamp_metadata: timestamp_metadata,
      value_metadata: value_metadata
    }

    <<compressed_data::binary-size(compressed_size), _rest::binary>> = data
    {:ok, metadata, compressed_data}
  end

  # Verify data integrity using checksum
  defp verify_data_integrity(%{checksum: expected_checksum}, data) do
    actual_checksum = :erlang.crc32(data)

    if actual_checksum == expected_checksum do
      :ok
    else
      {:error, "Checksum mismatch: expected #{expected_checksum}, got #{actual_checksum}"}
    end
  end

  # Convert 64-bit integer back to float
  defp bits_to_float(bits) do
    <<value::float-64>> = <<bits::64>>
    value
  end

  @doc """
  Validates metadata header format without full parsing.

  ## Parameters
  - `binary`: Binary data that should start with metadata header

  ## Returns
  - `:ok` if valid, `{:error, reason}` if invalid
  """
  def validate_metadata_header(binary) when is_binary(binary) do
    if byte_size(binary) < 80 do
      {:error, "Binary too small to contain valid metadata header"}
    else
      <<magic::64, version::16, header_length::16, _rest::binary>> = binary

      cond do
        magic != @magic_number ->
          {:error, "Invalid magic number"}

        version > @version ->
          {:error, "Unsupported version: #{version}"}

        header_length not in [80, 84] ->
          {:error, "Invalid header length: #{header_length}"}

        byte_size(binary) < header_length ->
          {:error, "Binary smaller than declared header length"}

        true ->
          :ok
      end
    end
  end

  def validate_metadata_header(_), do: {:error, "Invalid input - not binary"}

  @doc """
  Extracts basic information from metadata header without full parsing.

  ## Parameters
  - `binary`: Binary data starting with metadata header

  ## Returns
  - `{:ok, info_map}` with basic info, or `{:error, reason}`
  """
  def get_header_info(binary) when is_binary(binary) do
    case validate_metadata_header(binary) do
      :ok ->
        <<
          _magic::64,
          version::16,
          header_length::16,
          count::32,
          compressed_size::32,
          original_size::32,
          checksum::32,
          first_timestamp::64,
          _rest::binary
        >> = binary

        compression_ratio = if original_size > 0, do: compressed_size / original_size, else: 0.0

        info = %{
          version: version,
          header_length: header_length,
          count: count,
          compressed_size: compressed_size,
          original_size: original_size,
          checksum: checksum,
          first_timestamp: first_timestamp,
          compression_ratio: compression_ratio
        }

        {:ok, info}

      error ->
        error
    end
  end

  def get_header_info(_), do: {:error, "Invalid input - not binary"}

  @doc """
  Checks if binary data contains a valid Gorilla metadata header.

  ## Parameters
  - `binary`: Binary data to check

  ## Returns
  - `true` if contains valid header, `false` otherwise
  """
  def has_valid_header?(binary) when is_binary(binary) do
    case validate_metadata_header(binary) do
      :ok -> true
      _ -> false
    end
  end

  def has_valid_header?(_), do: false

  @doc """
  Estimates the original data size from metadata.

  ## Parameters
  - `metadata`: Parsed metadata map

  ## Returns
  - Estimated original size in bytes
  """
  def estimate_original_size(%{count: count}) do
    # Each data point is {timestamp, float} = 8 + 8 = 16 bytes
    count * 16
  end

  def estimate_original_size(_), do: 0

  @doc """
  Calculates compression efficiency metrics from metadata.

  ## Parameters
  - `metadata`: Parsed metadata map

  ## Returns
  - Map with efficiency metrics
  """
  def calculate_efficiency_metrics(metadata) do
    compressed_size = Map.get(metadata, :compressed_size, 0)
    original_size = Map.get(metadata, :original_size, estimate_original_size(metadata))
    count = Map.get(metadata, :count, 0)

    compression_ratio = if original_size > 0, do: compressed_size / original_size, else: 0.0

    space_savings =
      if original_size > 0, do: (original_size - compressed_size) / original_size, else: 0.0

    bytes_per_point = if count > 0, do: compressed_size / count, else: 0.0

    %{
      compression_ratio: compression_ratio,
      space_savings: space_savings,
      bytes_per_point: bytes_per_point,
      compressed_size: compressed_size,
      original_size: original_size,
      data_points: count
    }
  end
end
