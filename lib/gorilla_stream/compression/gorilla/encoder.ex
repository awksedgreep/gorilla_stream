defmodule GorillaStream.Compression.Gorilla.Encoder do
  @moduledoc """
  Main encoder for the Gorilla compression algorithm.

  This module coordinates the compression pipeline:
  1. Separates timestamps and values from the input stream
  2. Applies delta-of-delta encoding to timestamps
  3. Applies XOR-based compression to values
  4. Packs both bitstreams together
  5. Adds metadata header

  The Gorilla algorithm is specifically designed for time series data with
  regularly spaced timestamps and slowly changing floating-point values.
  """

  alias GorillaStream.Compression.Encoder.{
    DeltaEncoding,
    ValueCompression,
    BitPacking,
    Metadata
  }

  @doc """
  Encodes a stream of {timestamp, float} tuples using the Gorilla compression algorithm.

  This is an optimized implementation that skips some validation checks for better performance.
  Input data is assumed to be valid {timestamp, float} tuples.

  ## Parameters
  - `data`: List of {timestamp, float} tuples

  ## Returns
  - `{:ok, encoded_data}`: When encoding is successful
  - `{:error, reason}`: When encoding fails
  """
  def encode([]), do: {:ok, <<>>}

  def encode(data) when is_list(data) and length(data) > 0 do
    # Fast path validation - check first few items to catch common errors early
    case validate_input_data_fast(data) do
      :ok ->
        try do
          # Optimized path - minimal validation for speed
          {timestamps, values} = separate_timestamps_and_values(data)

          # Direct encoding without error handling wrapper functions
          {ts_bits, ts_meta} = DeltaEncoding.encode(timestamps)
          {val_bits, val_meta} = ValueCompression.compress(values)
          {packed_binary, pack_meta} = BitPacking.pack({ts_bits, ts_meta}, {val_bits, val_meta})

          final_data = Metadata.add_metadata(packed_binary, pack_meta)
          {:ok, final_data}
        rescue
          error in RuntimeError ->
            if String.contains?(error.message, "Invalid data format") do
              {:error, "Invalid data format: all items must be {timestamp, float} tuples"}
            else
              {:error, "Encoding failed: #{inspect(error)}"}
            end

          error ->
            {:error, "Encoding failed: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def encode(_), do: {:error, "Invalid input data - expected list of {timestamp, float} tuples"}

  # Fast validation that checks input format without full enumeration
  defp validate_input_data_fast(data) do
    # Check first item and a sample to catch common errors quickly
    case data do
      [first | _] when not is_tuple(first) ->
        {:error, "Invalid data format: all items must be {timestamp, float} tuples"}

      [first | _] when tuple_size(first) != 2 ->
        {:error, "Invalid data format: all items must be {timestamp, float} tuples"}

      [{timestamp, _} | _] when not is_integer(timestamp) ->
        {:error, "Invalid data format: all items must be {timestamp, float} tuples"}

      [{_, value} | _] when not is_number(value) ->
        {:error, "Invalid data format: all items must be {timestamp, float} tuples"}

      _ ->
        :ok
    end
  end

  # Validate that all input data points are properly formatted
  defp validate_input_data(data) do
    if Enum.all?(data, &valid_data_point?/1) do
      :ok
    else
      {:error, "Invalid data format: all items must be {timestamp, float} tuples"}
    end
  end

  # Check if a single data point is valid
  defp valid_data_point?({timestamp, value})
       when is_integer(timestamp) and (is_float(value) or is_integer(value)) do
    true
  end

  defp valid_data_point?(_), do: false

  # Separate the input stream into timestamps and values (single-pass optimization)
  defp separate_timestamps_and_values(data) do
    {timestamps, values} =
      Enum.reduce(data, {[], []}, fn
        {timestamp, value}, {ts_acc, val_acc} when is_integer(timestamp) and is_number(value) ->
          normalized_value =
            case value do
              val when is_float(val) -> val
              val when is_integer(val) -> val * 1.0
            end

          {[timestamp | ts_acc], [normalized_value | val_acc]}

        invalid_item, _acc ->
          raise "Invalid data format: expected {timestamp, float} tuple, got #{inspect(invalid_item)}"
      end)

    {Enum.reverse(timestamps), Enum.reverse(values)}
  end

  @doc """
  Estimates the compression ratio for given data without full compression.

  This is useful for determining if Gorilla compression would be beneficial
  for a particular dataset.

  ## Parameters
  - `data`: List of {timestamp, float} tuples

  ## Returns
  - `{:ok, estimated_ratio}`: Estimated compression ratio (compressed_size / original_size)
  - `{:error, reason}`: If estimation fails
  """
  def estimate_compression_ratio(data) when is_list(data) do
    try do
      case validate_input_data(data) do
        :ok ->
          # 8 bytes timestamp + 8 bytes float
          original_size = length(data) * 16

          if original_size == 0 do
            {:ok, 0.0}
          else
            # Quick estimation based on data characteristics
            {timestamps, values} = separate_timestamps_and_values(data)

            timestamp_estimate = estimate_timestamp_compression(timestamps)
            value_estimate = estimate_value_compression(values)

            # Add overhead for metadata and headers
            # bytes for metadata header
            overhead = 64
            estimated_compressed_size = timestamp_estimate + value_estimate + overhead

            ratio = estimated_compressed_size / original_size
            # Cap at 1.0 (no compression benefit)
            {:ok, min(1.0, ratio)}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, "Estimation failed: #{inspect(error)}"}
    end
  end

  def estimate_compression_ratio(_), do: {:error, "Invalid input data"}

  # Estimate timestamp compression efficiency
  defp estimate_timestamp_compression([]), do: 0
  # Single timestamp
  defp estimate_timestamp_compression([_]), do: 8

  defp estimate_timestamp_compression(timestamps) do
    # Calculate deltas and delta-of-deltas to estimate compression
    deltas = calculate_deltas(timestamps)
    delta_of_deltas = calculate_deltas(deltas)

    # Estimate bits needed based on delta-of-delta distribution
    avg_bits_per_dod = estimate_average_bits_per_delta_of_delta(delta_of_deltas)

    # First timestamp (64 bits) + first delta estimate + subsequent DoDs
    total_bits =
      64 + estimate_first_delta_bits(List.first(deltas, 0)) +
        length(delta_of_deltas) * trunc(avg_bits_per_dod)

    # Convert to bytes, ensure minimum 1 byte
    max(1, div(trunc(total_bits), 8))
  end

  # Estimate value compression efficiency
  defp estimate_value_compression([]), do: 0
  # Single value
  defp estimate_value_compression([_]), do: 8

  defp estimate_value_compression(values) do
    # Calculate XOR differences to estimate compression
    xor_diffs = calculate_xor_differences(values)

    # Count zero XORs (perfect matches)
    zero_xors = Enum.count(xor_diffs, &(&1 == 0))

    # Estimate average bits for non-zero XORs
    non_zero_xors = Enum.reject(xor_diffs, &(&1 == 0))

    avg_bits_per_xor =
      if length(non_zero_xors) > 0 do
        estimate_average_bits_per_xor(non_zero_xors)
      else
        # Minimum control bits
        2
      end

    # First value (64 bits) + zero XORs (1 bit each) + non-zero XORs
    total_bits = 64 + zero_xors + length(non_zero_xors) * trunc(avg_bits_per_xor)
    # Convert to bytes, ensure minimum 1 byte
    max(1, div(trunc(total_bits), 8))
  end

  # Helper functions for estimation
  defp calculate_deltas([]), do: []
  defp calculate_deltas([_]), do: []

  defp calculate_deltas([a, b | rest]) do
    [b - a | calculate_deltas([b | rest])]
  end

  # defp calculate_xor_differences([]), do: []
  defp calculate_xor_differences([_]), do: []

  defp calculate_xor_differences([a, b | rest]) do
    import Bitwise
    a_bits = float_to_bits(a)
    b_bits = float_to_bits(b)
    [bxor(a_bits, b_bits) | calculate_xor_differences([b | rest])]
  end

  # Convert float to 64-bit integer representation
  defp float_to_bits(value) when is_float(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end

  defp float_to_bits(value) when is_integer(value) do
    float_to_bits(value * 1.0)
  end

  defp estimate_first_delta_bits(delta) do
    cond do
      delta == 0 -> 1
      delta >= -63 and delta <= 64 -> 9
      delta >= -255 and delta <= 256 -> 12
      delta >= -2047 and delta <= 2048 -> 16
      true -> 36
    end
  end

  defp estimate_average_bits_per_delta_of_delta(dods) do
    if length(dods) == 0 do
      # Default estimate
      4
    else
      # Calculate distribution of delta-of-delta sizes
      bit_counts =
        Enum.map(dods, fn dod ->
          cond do
            dod == 0 -> 1
            dod >= -63 and dod <= 64 -> 9
            dod >= -255 and dod <= 256 -> 12
            dod >= -2047 and dod <= 2048 -> 16
            true -> 36
          end
        end)

      # Safe division
      case length(bit_counts) do
        0 -> 4.0
        len -> Enum.sum(bit_counts) / len
      end
    end
  end

  defp estimate_average_bits_per_xor(xors) do
    if length(xors) == 0 do
      # Default estimate
      20
    else
      # Rough estimate based on typical XOR patterns
      # This is a simplified estimation - actual compression depends on
      # leading/trailing zero patterns
      # Average estimate - each XOR typically needs ~15 bits
      15.0
    end
  end
end
