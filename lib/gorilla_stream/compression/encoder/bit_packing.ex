defmodule GorillaStream.Compression.Encoder.BitPacking do
  @moduledoc """
  Bit packing module for combining timestamp deltas and compressed values into a single bitstream.

  This module takes the output from delta encoding and value compression and packs them
  into an efficient binary format for the Gorilla compression algorithm.

  The format is:
  1. Header with metadata about the data
  2. Timestamp-encoded bitstream
  3. Value-encoded bitstream
  4. Padding to byte boundary if necessary
  """

  @doc """
  Packs timestamp deltas and compressed values into a single binary stream.

  ## Parameters
  - `{timestamp_bits, timestamp_metadata}`: Encoded timestamp data from DeltaEncoding
  - `{value_bits, value_metadata}`: Encoded value data from ValueCompression

  ## Returns
  - `{packed_binary, combined_metadata}`: Packed binary data and metadata
  """
  def pack({timestamp_bits, timestamp_metadata}, {value_bits, value_metadata}) do
    # Ensure both datasets have the same count
    if timestamp_metadata.count != value_metadata.count do
      raise "Timestamp and value counts must match: #{timestamp_metadata.count} vs #{value_metadata.count}"
    end

    count = timestamp_metadata.count

    if count == 0 do
      {<<>>, %{count: 0}}
    else
      # Calculate bit lengths
      timestamp_bit_length = bit_size(timestamp_bits)
      value_bit_length = bit_size(value_bits)

      # Create header with metadata
      header =
        create_header(
          count,
          timestamp_metadata,
          value_metadata,
          timestamp_bit_length,
          value_bit_length
        )

      # Combine all bits
      combined_bits = <<
        header::bitstring,
        timestamp_bits::bitstring,
        value_bits::bitstring
      >>

      # Pad to byte boundary
      padded_bits = pad_to_byte_boundary(combined_bits)

      combined_metadata = %{
        count: count,
        timestamp_metadata: timestamp_metadata,
        value_metadata: value_metadata,
        timestamp_bit_length: timestamp_bit_length,
        value_bit_length: value_bit_length,
        total_bits: bit_size(padded_bits)
      }

      {padded_bits, combined_metadata}
    end
  end

  # Create header with essential metadata for unpacking
  defp create_header(count, timestamp_meta, value_meta, timestamp_bits_len, value_bits_len) do
    # Header format:
    # - 32 bits: count
    # - 64 bits: first timestamp
    # - 64 bits: first value (as bits)
    # - 32 bits: first delta (if count > 1, otherwise 0)
    # - 32 bits: timestamp bitstream length
    # - 32 bits: value bitstream length

    first_timestamp = Map.get(timestamp_meta, :first_timestamp, 0)

    first_value_bits =
      if value_meta.count > 0 do
        float_to_bits(value_meta.first_value)
      else
        0
      end

    first_delta = Map.get(timestamp_meta, :first_delta, 0)

    <<
      count::32,
      first_timestamp::64,
      first_value_bits::64,
      first_delta::32-signed,
      timestamp_bits_len::32,
      value_bits_len::32
    >>
  end

  # Convert float to 64-bit integer representation
  defp float_to_bits(value) when is_float(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end

  defp float_to_bits(value) when is_integer(value) do
    float_to_bits(value * 1.0)
  end

  # Pad bitstring to byte boundary
  defp pad_to_byte_boundary(bits) do
    bit_length = bit_size(bits)
    remainder = rem(bit_length, 8)

    if remainder == 0 do
      bits
    else
      padding_bits = 8 - remainder
      <<bits::bitstring, 0::size(padding_bits)>>
    end
  end

  @doc """
  Unpacks binary data back into timestamp and value bitstreams.

  ## Parameters
  - `packed_binary`: The packed binary data

  ## Returns
  - `{timestamp_bits, value_bits, metadata}`: Unpacked components
  """
  def unpack(<<>>) do
    {<<>>, <<>>, %{count: 0}}
  end

  def unpack(packed_binary) when is_binary(packed_binary) do
    # Extract header (32 + 64 + 64 + 32 + 32 + 32 = 256 bits = 32 bytes)
    if byte_size(packed_binary) < 32 do
      {<<>>, <<>>, %{count: 0}}
    else
      <<
        count::32,
        first_timestamp::64,
        first_value_bits::64,
        first_delta::32-signed,
        timestamp_bits_len::32,
        value_bits_len::32,
        remaining::binary
      >> = packed_binary

      if count == 0 do
        {<<>>, <<>>, %{count: 0}}
      else
        # Extract timestamp and value bitstreams
        total_data_bits = timestamp_bits_len + value_bits_len
        # Round up to next byte
        total_data_bytes = div(total_data_bits + 7, 8)

        if byte_size(remaining) >= total_data_bytes do
          <<data_bits::bitstring-size(total_data_bits), _padding::binary>> = remaining

          <<
            timestamp_bits::bitstring-size(timestamp_bits_len),
            value_bits::bitstring-size(value_bits_len)
          >> = data_bits

          # Reconstruct metadata
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
            count: count,
            timestamp_metadata: timestamp_metadata,
            value_metadata: value_metadata,
            timestamp_bit_length: timestamp_bits_len,
            value_bit_length: value_bits_len
          }

          {timestamp_bits, value_bits, metadata}
        else
          {<<>>, <<>>, %{count: 0}}
        end
      end
    end
  end

  # Convert 64-bit integer back to float
  defp bits_to_float(bits) do
    <<value::float-64>> = <<bits::64>>
    value
  end
end
