defmodule GorillaStream.Compression.Decoder.DeltaDecoding do
  @moduledoc """
  Delta-of-delta decoding for timestamps in the Gorilla compression algorithm.

  This module reverses the delta-of-delta encoding process to reconstruct
  the original timestamps from the compressed bitstream.

  The decoding process:
  1. Read the first timestamp (64 bits)
  2. Read the first delta (variable length)
  3. For subsequent values, read delta-of-delta values and reconstruct timestamps:
     - '0' bit: delta-of-delta is 0 (same interval as previous)
     - '10' + 7 bits: delta-of-delta in range [-63, 64]
     - '110' + 9 bits: delta-of-delta in range [-255, 256]
     - '1110' + 12 bits: delta-of-delta in range [-2047, 2048]
     - '1111' + 32 bits: delta-of-delta as 32-bit signed integer
  """

  @doc """
  Decodes timestamp bitstream back into a list of timestamps.

  ## Parameters
  - `timestamp_bits`: Bitstream containing encoded timestamps
  - `metadata`: Metadata containing count and first timestamp info

  ## Returns
  - `{:ok, timestamps}`: List of decoded timestamps
  - `{:error, reason}`: If decoding fails
  """
  def decode(<<>>, %{count: 0}), do: {:ok, []}

  def decode(timestamp_bits, metadata) when is_bitstring(timestamp_bits) and is_map(metadata) do
    count = Map.get(metadata, :count, 0)

    cond do
      count == 0 and bit_size(timestamp_bits) == 0 ->
        # Empty data with count 0 is valid
        {:ok, []}

      count == 0 ->
        # Count 0 but has data - return empty (metadata says no timestamps)
        {:ok, []}

      bit_size(timestamp_bits) == 0 ->
        # No data but count > 0 - error
        {:error, "Invalid input - expected bitstring and metadata"}

      true ->
        try do
          case count do
            1 -> decode_single_timestamp(timestamp_bits)
            _ -> decode_multiple_timestamps(timestamp_bits, metadata)
          end
        rescue
          error ->
            {:error, "Delta decoding failed: #{inspect(error)}"}
        end
    end
  end

  def decode(_, _), do: {:error, "Invalid input - expected bitstring and metadata"}

  # Decode a single timestamp
  defp decode_single_timestamp(<<timestamp::64, _rest::bitstring>>) do
    {:ok, [timestamp]}
  end

  defp decode_single_timestamp(_) do
    {:error, "Insufficient data for single timestamp"}
  end

  # Decode multiple timestamps using delta-of-delta
  defp decode_multiple_timestamps(bits, metadata) do
    count = metadata.count

    case extract_initial_values(bits) do
      {:ok, {first_timestamp, first_delta, remaining_bits}} ->
        second_timestamp = first_timestamp + first_delta

        if count == 2 do
          {:ok, [first_timestamp, second_timestamp]}
        else
          # Decode remaining timestamps while reconstructing them on the fly
          # Note: We build the list in reverse for O(1) prepend, then reverse at the end
          decode_remaining_timestamps(
            remaining_bits,
            count - 2,
            first_delta,
            second_timestamp,
            [second_timestamp, first_timestamp]
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract first timestamp and first delta from bitstream
  defp extract_initial_values(<<first_timestamp::64, rest::bitstring>>) do
    case decode_first_delta(rest) do
      {:ok, {first_delta, remaining}} ->
        {:ok, {first_timestamp, first_delta, remaining}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_initial_values(_) do
    {:error, "Insufficient data for initial values"}
  end

  # Decode the first delta (between first and second timestamp)
  defp decode_first_delta(<<0::1, rest::bitstring>>) do
    {:ok, {0, rest}}
  end

  defp decode_first_delta(<<1::1, 0::1, delta::7-signed, rest::bitstring>>) do
    {:ok, {delta, rest}}
  end

  defp decode_first_delta(<<1::1, 1::1, 0::1, delta::9-signed, rest::bitstring>>) do
    {:ok, {delta, rest}}
  end

  defp decode_first_delta(<<1::1, 1::1, 1::1, 0::1, delta::12-signed, rest::bitstring>>) do
    {:ok, {delta, rest}}
  end

  defp decode_first_delta(<<1::1, 1::1, 1::1, 1::1, delta::32-signed, rest::bitstring>>) do
    {:ok, {delta, rest}}
  end

  defp decode_first_delta(_) do
    {:error, "Invalid or insufficient data for first delta"}
  end

  # Decode a single delta-of-delta value
  defp decode_single_delta_of_delta(<<0::1, rest::bitstring>>) do
    # Delta-of-delta is 0
    {:ok, {0, rest}}
  end

  defp decode_single_delta_of_delta(<<1::1, 0::1, dod::7-signed, rest::bitstring>>) do
    # Delta-of-delta in 7 bits
    {:ok, {dod, rest}}
  end

  defp decode_single_delta_of_delta(<<1::1, 1::1, 0::1, dod::9-signed, rest::bitstring>>) do
    # Delta-of-delta in 9 bits
    {:ok, {dod, rest}}
  end

  defp decode_single_delta_of_delta(<<1::1, 1::1, 1::1, 0::1, dod::12-signed, rest::bitstring>>) do
    # Delta-of-delta in 12 bits
    {:ok, {dod, rest}}
  end

  defp decode_single_delta_of_delta(<<1::1, 1::1, 1::1, 1::1, dod::32-signed, rest::bitstring>>) do
    # Delta-of-delta in 32 bits
    {:ok, {dod, rest}}
  end

  defp decode_single_delta_of_delta(bits) when bit_size(bits) < 4 do
    {:error, "Insufficient bits for delta-of-delta"}
  end

  defp decode_single_delta_of_delta(_) do
    {:error, "Invalid delta-of-delta encoding"}
  end

  # Decode delta-of-deltas and reconstruct timestamps in one pass
  defp decode_remaining_timestamps(_bits, 0, _prev_delta, _last_timestamp, acc) do
    # Reverse the accumulated list since we built it backwards for O(1) prepend
    {:ok, Enum.reverse(acc)}
  end

  defp decode_remaining_timestamps(bits, count, prev_delta, last_timestamp, acc) when count > 0 do
    case decode_single_delta_of_delta(bits) do
      {:ok, {dod, remaining_bits}} ->
        current_delta = prev_delta + dod
        next_timestamp = last_timestamp + current_delta

        decode_remaining_timestamps(
          remaining_bits,
          count - 1,
          current_delta,
          next_timestamp,
          # O(1) prepend instead of O(n) append
          [next_timestamp | acc]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates that a timestamp bitstream can be properly decoded.

  ## Parameters
  - `timestamp_bits`: Bitstream to validate
  - `expected_count`: Expected number of timestamps

  ## Returns
  - `:ok` if valid, `{:error, reason}` if invalid
  """
  def validate_bitstream(timestamp_bits, expected_count)
      when is_bitstring(timestamp_bits) and is_integer(expected_count) do
    cond do
      bit_size(timestamp_bits) == 0 and expected_count == 0 ->
        :ok

      bit_size(timestamp_bits) == 0 ->
        {:error, "Invalid input - expected bitstring"}

      true ->
        metadata = %{count: expected_count}

        case decode(timestamp_bits, metadata) do
          {:ok, timestamps} ->
            if length(timestamps) == expected_count do
              :ok
            else
              {:error,
               "Decoded count mismatch: expected #{expected_count}, got #{length(timestamps)}"}
            end

          {:error, reason} ->
            {:error, "Validation failed: #{reason}"}
        end
    end
  end

  def validate_bitstream(_, _), do: {:error, "Invalid input - expected bitstring"}

  @doc """
  Gets information about a timestamp bitstream without full decoding.

  ## Parameters
  - `timestamp_bits`: Bitstream to analyze
  - `metadata`: Metadata with count information

  ## Returns
  - `{:ok, info}` with basic information, or `{:error, reason}`
  """
  def get_bitstream_info(timestamp_bits, metadata)
      when is_bitstring(timestamp_bits) and is_map(metadata) do
    try do
      count = Map.get(metadata, :count)

      case {count, bit_size(timestamp_bits)} do
        {nil, _} ->
          {:error, "Invalid input"}

        {0, 0} ->
          {:ok, %{count: 0, first_timestamp: nil, estimated_range: nil}}

        {0, _} ->
          {:ok, %{count: 0, first_timestamp: nil, estimated_range: nil}}

        {_, 0} ->
          {:error, "Invalid input"}

        {1, _} ->
          case timestamp_bits do
            <<first::64, _rest::bitstring>> ->
              {:ok, %{count: 1, first_timestamp: first, estimated_range: 0}}

            _ ->
              {:error, "Insufficient data"}
          end

        {count, _} ->
          case extract_initial_values(timestamp_bits) do
            {:ok, {first_timestamp, first_delta, _}} ->
              estimated_last = first_timestamp + (count - 1) * first_delta
              estimated_range = estimated_last - first_timestamp

              {:ok,
               %{
                 count: count,
                 first_timestamp: first_timestamp,
                 first_delta: first_delta,
                 estimated_range: estimated_range
               }}

            {:error, reason} ->
              {:error, reason}
          end
      end
    rescue
      error ->
        {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  def get_bitstream_info(_, _), do: {:error, "Invalid input"}
end
