defmodule GorillaStream.Compression.Decoder.BitUnpacking do
  @moduledoc """
  Bit unpacking module for extracting timestamp and value bitstreams from packed binary data.

  This module reverses the bit packing process to separate the combined bitstream
  back into its timestamp and value components for individual decompression.

  The unpacking process:
  1. Uses metadata to determine bitstream lengths
  2. Extracts timestamp bitstream
  3. Extracts value bitstream
  4. Returns both components with metadata for decompression
  """

  @doc """
  Unpacks binary data into timestamp and value bitstreams using metadata.

  ## Parameters
  - `packed_data`: Binary data containing packed timestamp and value bitstreams

  ## Returns
  - `{timestamp_bits, value_bits, metadata}`: Tuple containing unpacked components and metadata
  """
  def unpack(<<>>) do
    {<<>>, <<>>, %{count: 0}}
  end

  def unpack(packed_data) when is_binary(packed_data) do
    # The packed data format from BitPacking.pack is:
    # - Header with metadata (32 + 64 + 64 + 32 + 32 + 32 = 256 bits = 32 bytes)
    # - Timestamp bitstream
    # - Value bitstream
    # - Padding to byte boundary

    if byte_size(packed_data) < 32 do
      # Not enough data for header
      {<<>>, <<>>, %{count: 0}}
    else
      case extract_header(packed_data) do
        {:ok, header_metadata, remaining_data} ->
          case extract_bitstreams(remaining_data, header_metadata) do
            {:ok, timestamp_bits, value_bits} ->
              # Reconstruct full metadata
              metadata = build_metadata(header_metadata)
              {timestamp_bits, value_bits, metadata}

            {:error, _reason} ->
              {<<>>, <<>>, %{count: 0}}
          end

        {:error, _reason} ->
          {<<>>, <<>>, %{count: 0}}
      end
    end
  end

  def unpack(_) do
    {<<>>, <<>>, %{count: 0}}
  end

  # Extract header information from packed data
  defp extract_header(<<
         count::32,
         first_timestamp::64,
         first_value_bits::64,
         first_delta::32-signed,
         timestamp_bits_len::32,
         value_bits_len::32,
         remaining::binary
       >>) do
    header = %{
      count: count,
      first_timestamp: first_timestamp,
      first_value_bits: first_value_bits,
      first_delta: first_delta,
      timestamp_bit_length: timestamp_bits_len,
      value_bit_length: value_bits_len
    }

    {:ok, header, remaining}
  end

  defp extract_header(_) do
    {:error, "Invalid header format"}
  end

  # Extract timestamp and value bitstreams from remaining data
  defp extract_bitstreams(remaining_data, header) do
    timestamp_bits_len = header.timestamp_bit_length
    value_bits_len = header.value_bit_length
    total_bits = timestamp_bits_len + value_bits_len

    if total_bits == 0 do
      {:ok, <<>>, <<>>}
    else
      # Calculate required bytes (rounded up)
      total_bytes_needed = div(total_bits + 7, 8)

      if byte_size(remaining_data) >= total_bytes_needed do
        # Extract the exact number of bits we need
        # Since the total bits might not align to byte boundary, we need to handle this carefully
        remaining_bits = bit_size(remaining_data)

        if remaining_bits >= total_bits do
          # Extract all remaining data as bitstring, then take what we need
          <<all_bits::bitstring>> = remaining_data
          <<data_bits::bitstring-size(total_bits), _padding::bitstring>> = all_bits

          # Split into timestamp and value components
          <<
            timestamp_bits::bitstring-size(timestamp_bits_len),
            value_bits::bitstring-size(value_bits_len)
          >> = data_bits

          {:ok, timestamp_bits, value_bits}
        else
          {:error, "Insufficient bits for bitstreams"}
        end
      else
        {:error, "Insufficient data for bitstreams"}
      end
    end
  end

  # Build complete metadata structure for decompression
  defp build_metadata(header) do
    count = header.count
    first_value = bits_to_float(header.first_value_bits)

    timestamp_metadata = %{
      count: count,
      first_timestamp: header.first_timestamp,
      first_delta: if(count > 1, do: header.first_delta, else: nil)
    }

    value_metadata = %{
      count: count,
      first_value: first_value
    }

    %{
      count: count,
      timestamp_metadata: timestamp_metadata,
      value_metadata: value_metadata,
      timestamp_bit_length: header.timestamp_bit_length,
      value_bit_length: header.value_bit_length
    }
  end

  # Convert 64-bit integer back to float
  defp bits_to_float(bits) do
    <<value::float-64>> = <<bits::64>>
    value
  end

  @doc """
  Validates that packed data can be properly unpacked.

  ## Parameters
  - `packed_data`: Binary data to validate

  ## Returns
  - `:ok` if valid, `{:error, reason}` if invalid
  """
  def validate_packed_data(packed_data) when is_binary(packed_data) do
    case unpack(packed_data) do
      {timestamp_bits, value_bits, metadata} ->
        count = Map.get(metadata, :count, 0)
        timestamp_bit_len = bit_size(timestamp_bits)
        value_bit_len = bit_size(value_bits)

        expected_timestamp_len = Map.get(metadata, :timestamp_bit_length, 0)
        expected_value_len = Map.get(metadata, :value_bit_length, 0)

        cond do
          count < 0 ->
            {:error, "Invalid count: #{count}"}

          timestamp_bit_len != expected_timestamp_len ->
            {:error,
             "Timestamp bitstream length mismatch: expected #{expected_timestamp_len}, got #{timestamp_bit_len}"}

          value_bit_len != expected_value_len ->
            {:error,
             "Value bitstream length mismatch: expected #{expected_value_len}, got #{value_bit_len}"}

          true ->
            :ok
        end
    end
  end

  def validate_packed_data(_), do: {:error, "Invalid input - expected binary data"}

  @doc """
  Gets information about packed data without full unpacking.

  ## Parameters
  - `packed_data`: Binary data to analyze

  ## Returns
  - `{:ok, info}` with basic information, or `{:error, reason}`
  """
  def get_packed_info(packed_data) when is_binary(packed_data) do
    if byte_size(packed_data) < 32 do
      {:error, "Data too small for valid header"}
    else
      case extract_header(packed_data) do
        {:ok, header, remaining_data} ->
          info = %{
            total_size: byte_size(packed_data),
            header_size: 32,
            data_size: byte_size(remaining_data),
            count: header.count,
            timestamp_bit_length: header.timestamp_bit_length,
            value_bit_length: header.value_bit_length,
            total_bit_length: header.timestamp_bit_length + header.value_bit_length,
            first_timestamp: header.first_timestamp,
            first_value: bits_to_float(header.first_value_bits),
            first_delta: if(header.count > 1, do: header.first_delta, else: nil)
          }

          {:ok, info}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def get_packed_info(_), do: {:error, "Invalid input - expected binary data"}

  @doc """
  Estimates unpacking performance for given packed data.

  ## Parameters
  - `packed_data`: Binary data to analyze

  ## Returns
  - `{:ok, performance_info}`: Performance estimates
  - `{:error, reason}`: If analysis fails
  """
  def estimate_unpacking_performance(packed_data) when is_binary(packed_data) do
    case get_packed_info(packed_data) do
      {:ok, info} ->
        # Simple performance estimates
        estimated_time_ms = estimate_unpacking_time(info)
        estimated_memory_kb = estimate_memory_usage(info)

        performance = %{
          estimated_unpacking_time_ms: estimated_time_ms,
          estimated_memory_usage_kb: estimated_memory_kb,
          data_points: info.count,
          bitstream_efficiency: calculate_bitstream_efficiency(info)
        }

        {:ok, performance}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def estimate_unpacking_performance(_), do: {:error, "Invalid input"}

  # Estimate unpacking time based on data characteristics
  defp estimate_unpacking_time(info) do
    # Very rough estimate: base time + time per bit
    base_time = 0.01
    per_bit_time = 0.000001
    base_time + info.total_bit_length * per_bit_time
  end

  # Estimate memory usage during unpacking
  defp estimate_memory_usage(info) do
    # Rough estimate: bitstreams + metadata + overhead
    # Convert to KB
    bitstream_memory = info.total_bit_length / 8 / 1024
    # Small overhead for metadata
    metadata_memory = 1
    overhead = 0.5
    bitstream_memory + metadata_memory + overhead
  end

  # Calculate bitstream packing efficiency
  defp calculate_bitstream_efficiency(info) do
    if info.count > 0 do
      # Original size would be count * (8 bytes timestamp + 8 bytes value) * 8 bits/byte
      original_bits = info.count * 16 * 8
      compressed_bits = info.total_bit_length

      if original_bits > 0 do
        compressed_bits / original_bits
      else
        0.0
      end
    else
      0.0
    end
  end
end
