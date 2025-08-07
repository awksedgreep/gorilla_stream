defmodule GorillaStream.Compression.Encoder.ValueCompression do
  @moduledoc """
  XOR-based value compression for floating-point values as used in the Gorilla algorithm.

  The algorithm works as follows:
  1. Store the first value as-is (64 bits)
  2. For subsequent values:
     - XOR the value with the previous value
     - If XOR result is 0: store single bit '0'
     - If XOR result is non-zero:
       - Count leading zeros and trailing zeros
       - If leading/trailing zero counts match the previous value's pattern:
         store '10' + meaningful bits only
       - Otherwise: store '11' + 5 bits for leading zeros + 6 bits for length + meaningful bits

  This encoding is highly efficient for slowly changing floating-point time series data.
  """

  import Bitwise

  @doc """
  Compresses a list of float values using XOR-based compression.

  ## Parameters
  - `values`: List of float values

  ## Returns
  - `{encoded_bits, metadata}`: Tuple containing the encoded bits as binary and metadata
  """
  def compress([]), do: {<<>>, %{count: 0}}

  def compress([value]) do
    # Single value - store as-is
    value_bits = float_to_bits(value)
    {<<value_bits::64>>, %{count: 1, first_value: value}}
  end

  def compress([first | rest]) do
    # Store first value as-is (64 bits)
    first_bits = float_to_bits(first)
    bits = [<<first_bits::64>>]

    # Process remaining values with XOR compression
    initial_state = %{
      bits: bits,
      prev_value_bits: first_bits,
      prev_leading_zeros: 0,
      prev_trailing_zeros: 0
    }

    final_state = Enum.reduce(rest, initial_state, &encode_value/2)

    metadata = %{
      count: length([first | rest]),
      first_value: first
    }

    final_bits = :erlang.list_to_bitstring(final_state.bits)

    {final_bits, metadata}
  end

  # Encode a single value using XOR compression
  defp encode_value(value, state) do
    current_bits = float_to_bits(value)
    xor_result = bxor(current_bits, state.prev_value_bits)

    if xor_result == 0 do
      # Value is identical to previous - store single '0' bit
      %{state | bits: [state.bits, <<0::1>>], prev_value_bits: current_bits}
    else
      # Value differs - encode the XOR result
      encode_xor_result(xor_result, current_bits, state)
    end
  end

  # Encode the XOR result with variable-length encoding
  defp encode_xor_result(xor_result, current_bits, state) do
    leading_zeros = count_leading_zeros(xor_result)
    trailing_zeros = count_trailing_zeros(xor_result)
    meaningful_bits = 64 - leading_zeros - trailing_zeros

    if leading_zeros >= state.prev_leading_zeros and
         trailing_zeros >= state.prev_trailing_zeros and
         meaningful_bits > 0 do
      # Use previous window - store '10' + meaningful bits only
      _meaningful_start = state.prev_leading_zeros
      meaningful_length = 64 - state.prev_leading_zeros - state.prev_trailing_zeros

      if meaningful_length > 0 do
        meaningful_value =
          bsr(xor_result, state.prev_trailing_zeros) &&&
            (1 <<< meaningful_length) - 1

        %{
          state
          | bits: [state.bits, <<1::1, 0::1, meaningful_value::size(meaningful_length)>>],
            prev_value_bits: current_bits
        }
      else
        # Fallback to new window if meaningful_length is 0
        encode_new_window(
          xor_result,
          current_bits,
          state,
          leading_zeros,
          trailing_zeros,
          meaningful_bits
        )
      end
    else
      # Use new window - store '11' + 5 bits leading + 6 bits length + meaningful bits
      encode_new_window(
        xor_result,
        current_bits,
        state,
        leading_zeros,
        trailing_zeros,
        meaningful_bits
      )
    end
  end

  defp encode_new_window(
         xor_result,
         current_bits,
         state,
         leading_zeros,
         trailing_zeros,
         meaningful_bits
       ) do
    # Ensure meaningful_bits is at least 1 and at most 64
    adjusted_meaningful_bits = max(1, min(64, meaningful_bits))
    # 5 bits max
    adjusted_leading_zeros = max(0, min(31, leading_zeros))

    meaningful_value =
      if adjusted_meaningful_bits > 0 do
        bsr(xor_result, trailing_zeros) &&& (1 <<< adjusted_meaningful_bits) - 1
      else
        0
      end

    new_bits = [
      state.bits,
      <<
        # Control bits '11'
        1::1,
        1::1,
        # 5 bits for leading zeros
        adjusted_leading_zeros::5,
        # 6 bits for length (length - 1)
        adjusted_meaningful_bits - 1::6,
        # The meaningful bits
        meaningful_value::size(adjusted_meaningful_bits)
      >>
    ]

    %{
      state
      | bits: new_bits,
        prev_value_bits: current_bits,
        prev_leading_zeros: adjusted_leading_zeros,
        prev_trailing_zeros: trailing_zeros
    }
  end

  # Convert float to 64-bit integer representation
  defp float_to_bits(value) when is_float(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end

  defp float_to_bits(value) when is_integer(value) do
    float_to_bits(value * 1.0)
  end

  # Count leading zeros in a 64-bit integer
  defp count_leading_zeros(0), do: 64

  defp count_leading_zeros(value) do
    count_leading_zeros(value, 0)
  end

  defp count_leading_zeros(value, count) when (value &&& 1 <<< 63) != 0 do
    count
  end

  defp count_leading_zeros(value, count) when count < 64 do
    count_leading_zeros(value <<< 1, count + 1)
  end

  defp count_leading_zeros(_, count), do: count

  # Count trailing zeros in a 64-bit integer
  defp count_trailing_zeros(0), do: 64

  defp count_trailing_zeros(value) do
    count_trailing_zeros(value, 0)
  end

  defp count_trailing_zeros(value, count) when (value &&& 1) != 0 do
    count
  end

  defp count_trailing_zeros(value, count) when count < 64 do
    count_trailing_zeros(bsr(value, 1), count + 1)
  end

  defp count_trailing_zeros(_, count), do: count
end
