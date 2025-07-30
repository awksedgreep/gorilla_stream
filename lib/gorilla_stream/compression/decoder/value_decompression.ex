defmodule GorillaStream.Compression.Decoder.ValueDecompression do
  @moduledoc """
  XOR-based value decompression for floating-point values in the Gorilla algorithm.

  This module reverses the XOR-based compression process to reconstruct
  the original floating-point values from the compressed bitstream.

  The decoding process:
  1. Read the first value (64 bits)
  2. For subsequent values:
     - '0' bit: value is identical to previous
     - '10' + meaningful bits: use previous window for meaningful bits
     - '11' + 5 bits leading + 6 bits length + meaningful bits: use new window

  This decoding efficiently reconstructs slowly changing floating-point time series data.
  """

  import Bitwise

  @doc """
  Decompresses value bitstream back into a list of float values.

  ## Parameters
  - `value_bits`: Bitstream containing encoded values
  - `metadata`: Metadata containing count and first value info

  ## Returns
  - `{:ok, values}`: List of decoded float values
  - `{:error, reason}`: If decompression fails
  """
  def decompress(<<>>, %{count: 0}), do: {:ok, []}

  def decompress(value_bits, metadata) when is_bitstring(value_bits) do
    try do
      count = Map.get(metadata, :count, 0)

      case count do
        0 -> {:ok, []}
        1 -> decompress_single_value(value_bits)
        _ -> decompress_multiple_values(value_bits, metadata)
      end
    rescue
      error ->
        {:error, "Value decompression failed: #{inspect(error)}"}
    end
  end

  def decompress(_, _), do: {:error, "Invalid input - expected bitstring and metadata"}

  # Decompress a single value
  defp decompress_single_value(<<value_bits::64, _rest::bitstring>>) do
    value = bits_to_float(value_bits)
    {:ok, [value]}
  end

  defp decompress_single_value(_) do
    {:error, "Insufficient data for single value"}
  end

  # Decompress multiple values using XOR decompression
  defp decompress_multiple_values(bits, metadata) do
    count = metadata.count

    case extract_first_value(bits) do
      {:ok, {first_value, remaining_bits}} ->
        if count == 1 do
          {:ok, [first_value]}
        else
          # Decompress remaining values using XOR
          initial_state = %{
            bits: remaining_bits,
            prev_value_bits: float_to_bits(first_value),
            prev_leading_zeros: 0,
            prev_trailing_zeros: 0,
            values: [first_value]
          }

          case decompress_xor_values(initial_state, count - 1) do
            {:ok, final_state} ->
              {:ok, Enum.reverse(final_state.values)}

            {:error, reason} ->
              {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Extract first value from bitstream
  defp extract_first_value(<<value_bits::64, rest::bitstring>>) do
    value = bits_to_float(value_bits)
    {:ok, {value, rest}}
  end

  defp extract_first_value(_) do
    {:error, "Insufficient data for first value"}
  end

  # Decompress a sequence of XOR-encoded values using tail recursion optimization
  defp decompress_xor_values(state, remaining_count) do
    decompress_xor_values_loop(state, remaining_count)
  end

  # Tail-recursive loop for better performance
  defp decompress_xor_values_loop(state, 0), do: {:ok, state}

  defp decompress_xor_values_loop(state, remaining_count) when remaining_count > 0 do
    case decompress_single_xor_value(state) do
      {:ok, new_state} ->
        decompress_xor_values_loop(new_state, remaining_count - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decompress a single XOR-encoded value
  defp decompress_single_xor_value(%{bits: <<0::1, rest::bitstring>>} = state) do
    # Value is identical to previous - XOR result was 0
    prev_value = bits_to_float(state.prev_value_bits)

    {:ok,
     %{
       state
       | bits: rest,
         values: [prev_value | state.values]
     }}
  end

  defp decompress_single_xor_value(%{bits: <<1::1, 0::1, rest::bitstring>>} = state) do
    # Use previous window
    meaningful_length = 64 - state.prev_leading_zeros - state.prev_trailing_zeros

    if meaningful_length > 0 do
      case rest do
        <<meaningful_value::size(meaningful_length), remaining_bits::bitstring>> ->
          # Reconstruct XOR result
          xor_result = meaningful_value <<< state.prev_trailing_zeros

          # Apply XOR to get new value
          new_value_bits = bxor(state.prev_value_bits, xor_result)
          new_value = bits_to_float(new_value_bits)

          {:ok,
           %{
             state
             | bits: remaining_bits,
               prev_value_bits: new_value_bits,
               values: [new_value | state.values]
           }}

        _ ->
          {:error, "Insufficient bits for meaningful value"}
      end
    else
      {:error, "Invalid meaningful length in previous window"}
    end
  end

  defp decompress_single_xor_value(%{bits: <<1::1, 1::1, rest::bitstring>>} = state) do
    # Use new window
    case rest do
      <<leading_zeros::5, length_minus_one::6, remaining_bits::bitstring>> ->
        meaningful_length = length_minus_one + 1

        if meaningful_length > 0 and meaningful_length <= 64 do
          case remaining_bits do
            <<meaningful_value::size(meaningful_length), final_bits::bitstring>> ->
              # Calculate trailing zeros
              trailing_zeros = 64 - leading_zeros - meaningful_length

              if trailing_zeros >= 0 do
                # Reconstruct XOR result
                xor_result = meaningful_value <<< trailing_zeros

                # Apply XOR to get new value
                new_value_bits = bxor(state.prev_value_bits, xor_result)
                new_value = bits_to_float(new_value_bits)

                {:ok,
                 %{
                   state
                   | bits: final_bits,
                     prev_value_bits: new_value_bits,
                     prev_leading_zeros: leading_zeros,
                     prev_trailing_zeros: trailing_zeros,
                     values: [new_value | state.values]
                 }}
              else
                {:error, "Invalid trailing zeros calculation"}
              end

            _ ->
              {:error, "Insufficient bits for meaningful value in new window"}
          end
        else
          {:error, "Invalid meaningful length: #{meaningful_length}"}
        end

      _ ->
        {:error, "Insufficient bits for new window header"}
    end
  end

  defp decompress_single_xor_value(%{bits: bits}) when bit_size(bits) < 2 do
    {:error, "Insufficient bits for control bits"}
  end

  defp decompress_single_xor_value(_) do
    {:error, "Invalid XOR encoding"}
  end

  # Convert 64-bit integer back to float
  defp bits_to_float(bits) do
    <<value::float-64>> = <<bits::64>>
    value
  end

  # Convert float to 64-bit integer representation
  defp float_to_bits(value) when is_float(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end

  @doc """
  Validates that a value bitstream can be properly decompressed.

  ## Parameters
  - `value_bits`: Bitstream to validate
  - `expected_count`: Expected number of values

  ## Returns
  - `:ok` if valid, `{:error, reason}` if invalid
  """
  def validate_bitstream(value_bits, expected_count) when is_bitstring(value_bits) do
    metadata = %{count: expected_count, first_value: 0.0}

    case decompress(value_bits, metadata) do
      {:ok, values} ->
        if length(values) == expected_count do
          :ok
        else
          {:error, "Decoded count mismatch: expected #{expected_count}, got #{length(values)}"}
        end

      {:error, reason} ->
        {:error, "Validation failed: #{reason}"}
    end
  end

  def validate_bitstream(_, _), do: {:error, "Invalid input - expected bitstring"}

  @doc """
  Gets information about a value bitstream without full decompression.

  ## Parameters
  - `value_bits`: Bitstream to analyze
  - `metadata`: Metadata with count and first value information

  ## Returns
  - `{:ok, info}` with basic information, or `{:error, reason}`
  """
  def get_bitstream_info(value_bits, metadata) when is_bitstring(value_bits) do
    try do
      count = Map.get(metadata, :count, 0)
      first_value = Map.get(metadata, :first_value, 0.0)

      case count do
        0 ->
          {:ok, %{count: 0, first_value: nil, bitstream_size: 0}}

        1 ->
          {:ok, %{count: 1, first_value: first_value, bitstream_size: bit_size(value_bits)}}

        _ ->
          # Basic analysis without full decompression
          {:ok,
           %{
             count: count,
             first_value: first_value,
             bitstream_size: bit_size(value_bits),
             estimated_compression_ratio: estimate_compression_ratio(value_bits, count)
           }}
      end
    rescue
      error ->
        {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  def get_bitstream_info(_, _), do: {:error, "Invalid input"}

  # Estimate compression ratio based on bitstream characteristics
  defp estimate_compression_ratio(value_bits, count) do
    if count == 0 do
      0.0
    else
      # Original size: count * 8 bytes per float
      original_size_bits = count * 64
      compressed_size_bits = bit_size(value_bits)

      if original_size_bits > 0 do
        compressed_size_bits / original_size_bits
      else
        0.0
      end
    end
  end

  @doc """
  Decompresses values and validates they match expected characteristics.

  ## Parameters
  - `value_bits`: Bitstream containing encoded values
  - `metadata`: Metadata with expected characteristics
  - `validation_opts`: Optional validation parameters

  ## Returns
  - `{:ok, {values, stats}}`: Decompressed values and statistics
  - `{:error, reason}`: If decompression or validation fails
  """
  def decompress_and_validate(value_bits, metadata, validation_opts \\ []) do
    case decompress(value_bits, metadata) do
      {:ok, values} ->
        stats = calculate_statistics(values)

        case validate_characteristics(values, stats, validation_opts) do
          :ok ->
            {:ok, {values, stats}}

          {:error, reason} ->
            {:error, "Validation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Calculate basic statistics for decompressed values
  defp calculate_statistics([]), do: %{count: 0}

  defp calculate_statistics(values) do
    count = length(values)
    min_val = Enum.min(values)
    max_val = Enum.max(values)
    sum = Enum.sum(values)
    mean = sum / count

    # Calculate variance
    variance =
      values
      |> Enum.map(fn v -> (v - mean) * (v - mean) end)
      |> Enum.sum()
      |> Kernel./(count)

    %{
      count: count,
      min: min_val,
      max: max_val,
      mean: mean,
      variance: variance,
      range: max_val - min_val
    }
  end

  # Validate characteristics of decompressed values
  defp validate_characteristics(values, stats, opts) do
    expected_count = Keyword.get(opts, :expected_count)
    max_range = Keyword.get(opts, :max_range)
    min_values = Keyword.get(opts, :min_values, 1)

    cond do
      expected_count && stats.count != expected_count ->
        {:error, "Count mismatch: expected #{expected_count}, got #{stats.count}"}

      stats.count < min_values ->
        {:error, "Too few values: #{stats.count} < #{min_values}"}

      max_range && stats.range > max_range ->
        {:error, "Range too large: #{stats.range} > #{max_range}"}

      not Enum.all?(values, &is_number/1) ->
        {:error, "Invalid values detected"}

      not Enum.all?(values, &is_finite/1) ->
        {:error, "Non-finite values detected"}

      true ->
        :ok
    end
  end

  # Check if a number is finite (not NaN or infinity)
  defp is_finite(x) when is_float(x) do
    not (x != x or not is_finite_float(x))
  end

  defp is_finite(x) when is_integer(x), do: true
  defp is_finite(_), do: false

  # Helper to check if float is finite (not infinity)
  defp is_finite_float(x) when is_float(x) do
    x > -1.7976931348623157e308 and x < 1.7976931348623157e308
  end
end
