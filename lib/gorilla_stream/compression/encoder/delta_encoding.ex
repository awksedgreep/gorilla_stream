defmodule GorillaStream.Compression.Encoder.DeltaEncoding do
  @moduledoc """
  Delta-of-delta encoding for timestamps as used in the Gorilla compression algorithm.

  The algorithm works as follows:
  1. Store the first timestamp as-is (64 bits)
  2. Store the delta between the second and first timestamp (variable length)
  3. For subsequent timestamps, compute delta-of-delta and encode with variable length:
     - If delta-of-delta is 0: store single bit '0'
     - If delta-of-delta fits in [-63, 64]: store '10' + 7 bits
     - If delta-of-delta fits in [-255, 256]: store '110' + 9 bits
     - If delta-of-delta fits in [-2047, 2048]: store '1110' + 12 bits
     - Otherwise: store '1111' + 32 bits

  This encoding is highly efficient for regularly spaced time series data.
  """

  @doc """
  Encodes a list of timestamps using delta-of-delta compression.

  ## Parameters
  - `timestamps`: List of integer timestamps

  ## Returns
  - `{encoded_bits, metadata}`: Tuple containing the encoded bits as binary and metadata
  """
  def encode(timestamps) when not is_list(timestamps) do
    {:error, "Input must be a list of integers"}
  end

  def encode(timestamps) when not is_list(timestamps) do
    {:error, "Input must be a list of integers"}
  end

  def encode([]), do: {<<>>, %{count: 0}}

  def encode([timestamp]) when is_integer(timestamp) do
    # Single timestamp - just store it
    {<<timestamp::64>>, %{count: 1, first_timestamp: timestamp}}
  end

  def encode([first, second | rest]) when is_integer(first) and is_integer(second) do
    # Store first timestamp (64 bits)
    first_delta = second - first

    # Start with first timestamp and first delta
    bits = <<first::64, encode_first_delta(first_delta)::bitstring>>

    # Process remaining timestamps with delta-of-delta encoding
    {iodata, _, _} =
      Enum.reduce(rest, {[bits], first_delta, second}, fn timestamp,
                                                          {acc, prev_delta, prev_timestamp} ->
        current_delta = timestamp - prev_timestamp
        delta_of_delta = current_delta - prev_delta
        encoded_dod = encode_delta_of_delta(delta_of_delta)

        {[acc, encoded_dod], current_delta, timestamp}
      end)

    metadata = %{
      count: length([first, second | rest]),
      first_timestamp: first,
      first_delta: first_delta
    }

    {IO.iodata_to_binary(iodata), metadata}
  end

  # Encode the first delta (between first and second timestamp)
  # Use a simple variable-length encoding
  defp encode_first_delta(delta) when delta == 0 do
    <<0::1>>
  end

  defp encode_first_delta(delta) when delta >= -63 and delta <= 64 do
    <<1::1, 0::1, delta::7-signed>>
  end

  defp encode_first_delta(delta) when delta >= -255 and delta <= 256 do
    <<1::1, 1::1, 0::1, delta::9-signed>>
  end

  defp encode_first_delta(delta) when delta >= -2047 and delta <= 2048 do
    <<1::1, 1::1, 1::1, 0::1, delta::12-signed>>
  end

  defp encode_first_delta(delta) do
    <<1::1, 1::1, 1::1, 1::1, delta::32-signed>>
  end

  # Encode delta-of-delta with variable length encoding
  defp encode_delta_of_delta(0) do
    # Delta-of-delta is 0 - just one bit
    <<0::1>>
  end

  defp encode_delta_of_delta(dod) when dod >= -63 and dod <= 64 do
    # 2 control bits + 7 data bits
    <<1::1, 0::1, dod::7-signed>>
  end

  defp encode_delta_of_delta(dod) when dod >= -255 and dod <= 256 do
    # 3 control bits + 9 data bits
    <<1::1, 1::1, 0::1, dod::9-signed>>
  end

  defp encode_delta_of_delta(dod) when dod >= -2047 and dod <= 2048 do
    # 4 control bits + 12 data bits
    <<1::1, 1::1, 1::1, 0::1, dod::12-signed>>
  end

  defp encode_delta_of_delta(dod) do
    # 4 control bits + 32 data bits
    <<1::1, 1::1, 1::1, 1::1, dod::32-signed>>
  end
end
