defmodule GorillaStream.Compression.Gorilla.Decoder do
  @moduledoc """
  Main decoder for the Gorilla compression algorithm.

  This module coordinates the decompression pipeline:
  1. Extracts and validates metadata header
  2. Unpacks the combined bitstream into timestamp and value components
  3. Applies delta-of-delta decoding to timestamps
  4. Applies XOR-based decompression to values
  5. Recombines timestamps and values into the original stream

  The Gorilla algorithm is specifically designed for time series data with
  regularly spaced timestamps and slowly changing floating-point values.
  """

  alias GorillaStream.Compression.Decoder.{
    Metadata,
    BitUnpacking,
    DeltaDecoding,
    ValueDecompression
  }

  @doc """
  Decodes compressed binary data back into a stream of {timestamp, float} tuples.

  ## Parameters
  - `encoded_data`: Binary data to decode

  ## Returns
  - `{:ok, decoded_data}`: When decoding is successful
  - `{:error, reason}`: When decoding fails
  """
  def decode(<<>>), do: {:ok, []}

  def decode(encoded_data) when is_binary(encoded_data) do
    try do
      # Pipeline: metadata -> unpack -> decode timestamps -> decode values -> optional VM post -> combine
      with {:ok, extracted_metadata, remaining_data} <- extract_metadata(encoded_data),
           {:ok, timestamp_bits, value_bits, unpack_metadata} <- unpack_data(remaining_data),
           {:ok, timestamps} <- decode_timestamps(timestamp_bits, unpack_metadata),
           {:ok, values_raw} <- decode_values(value_bits, unpack_metadata),
           {:ok, values} <- maybe_vm_postprocess(values_raw, extracted_metadata),
           {:ok, combined_stream} <- combine_stream(timestamps, values) do
        {:ok, combined_stream}
      end
    rescue
      error ->
        {:error, "Decoding failed: #{inspect(error)}"}
    end
  end

  def decode(_), do: {:error, "Invalid input data"}

  # Extract metadata from encoded data
  defp extract_metadata(encoded_data) do
    try do
      {extracted_metadata, remaining_data} = Metadata.extract_metadata(encoded_data)
      {:ok, extracted_metadata, remaining_data}
    rescue
      error ->
        {:error, "Metadata extraction failed: #{inspect(error)}"}
    end
  end

  # Unpack combined bitstream into timestamp and value components
  defp unpack_data(packed_data) do
    try do
      {timestamp_bits, value_bits, metadata} = BitUnpacking.unpack(packed_data)
      {:ok, timestamp_bits, value_bits, metadata}
    rescue
      error ->
        {:error, "Bit unpacking failed: #{inspect(error)}"}
    end
  end

  # Decode timestamps using delta-of-delta decompression
  defp decode_timestamps(timestamp_bits, metadata) do
    try do
      timestamp_metadata = Map.get(metadata, :timestamp_metadata, %{})

      case DeltaDecoding.decode(timestamp_bits, timestamp_metadata) do
        {:ok, timestamps} ->
          {:ok, timestamps}

        {:error, reason} ->
          {:error, "Timestamp decoding failed: #{reason}"}
      end
    rescue
      error ->
        {:error, "Timestamp decoding failed: #{inspect(error)}"}
    end
  end

  # Decode values using XOR-based decompression
  defp decode_values(value_bits, metadata) do
    try do
      value_metadata = Map.get(metadata, :value_metadata, %{})

      case ValueDecompression.decompress(value_bits, value_metadata) do
        {:ok, values} ->
          {:ok, values}

        {:error, reason} ->
          {:error, "Value decompression failed: #{reason}"}
      end
    rescue
      error ->
        {:error, "Value decompression failed: #{inspect(error)}"}
    end
  end

  # Optional VictoriaMetrics-style postprocessing
  defp maybe_vm_postprocess(values, metadata) do
    import Bitwise
    flags = Map.get(metadata, :flags, 0)
    vm_enabled? = (flags &&& 0x1) != 0
    is_counter? = (flags &&& 0x2) != 0

    if vm_enabled? do
      n = Map.get(metadata, :scale_decimals, 0)
      scale = if n > 0, do: :math.pow(10, n), else: 1.0
      unscaled = if n > 0, do: Enum.map(values, &(&1 / scale)), else: values
      decoded = if is_counter?, do: GorillaStream.Compression.Enhancements.delta_decode_counter(unscaled), else: unscaled
      {:ok, decoded}
    else
      {:ok, values}
    end
  end

  # Combine timestamps and values back into original stream format
  defp combine_stream(timestamps, values) do
    try do
      if length(timestamps) != length(values) do
        {:error, "Timestamp and value count mismatch: #{length(timestamps)} vs #{length(values)}"}
      else
        combined = Enum.zip(timestamps, values)
        {:ok, combined}
      end
    rescue
      error ->
        {:error, "Stream combination failed: #{inspect(error)}"}
    end
  end

  @doc """
  Validates that compressed data can be properly decoded without full decompression.

  ## Parameters
  - `encoded_data`: Binary data to validate

  ## Returns
  - `:ok` if valid, `{:error, reason}` if invalid
  """
  def validate_compressed_data(encoded_data) when is_binary(encoded_data) do
    try do
      case extract_metadata(encoded_data) do
        {:ok, metadata, remaining_data} ->
          # Check if we have enough data for the declared content
          expected_size = calculate_expected_data_size(metadata)
          actual_size = byte_size(remaining_data)

          if actual_size >= expected_size do
            # Additional validation could be added here
            :ok
          else
            {:error, "Insufficient data: expected #{expected_size} bytes, got #{actual_size}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, "Validation failed: #{inspect(error)}"}
    end
  end

  def validate_compressed_data(_), do: {:error, "Invalid input - expected binary data"}

  # Calculate expected data size based on metadata
  defp calculate_expected_data_size(metadata) do
    # This is a rough estimate - actual implementation would be more precise
    count = Map.get(metadata, :count, 0)
    # Minimum: header + some data per point
    max(32, count * 2)
  end

  @doc """
  Gets information about compressed data without full decompression.

  ## Parameters
  - `encoded_data`: Binary data to analyze

  ## Returns
  - `{:ok, info}` with compression information, or `{:error, reason}`
  """
  def get_compression_info(encoded_data) when is_binary(encoded_data) do
    try do
      case extract_metadata(encoded_data) do
        {:ok, metadata, remaining_data} ->
          info = %{
            total_size: byte_size(encoded_data),
            metadata_size: byte_size(encoded_data) - byte_size(remaining_data),
            data_size: byte_size(remaining_data),
            count: Map.get(metadata, :count, 0),
            metadata: metadata
          }

          {:ok, info}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  def get_compression_info(_), do: {:error, "Invalid input - expected binary data"}

  @doc """
  Decodes and validates the result matches expected characteristics.

  ## Parameters
  - `encoded_data`: Binary data to decode
  - `validation_opts`: Optional validation parameters

  ## Returns
  - `{:ok, {stream, stats}}`: Decoded stream and statistics
  - `{:error, reason}`: If decoding or validation fails
  """
  def decode_and_validate(encoded_data, validation_opts \\ []) do
    case decode(encoded_data) do
      {:ok, stream} ->
        stats = calculate_stream_statistics(stream)

        case validate_stream_characteristics(stream, stats, validation_opts) do
          :ok ->
            {:ok, {stream, stats}}

          {:error, reason} ->
            {:error, "Validation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Calculate basic statistics for the decoded stream
  defp calculate_stream_statistics([]), do: %{count: 0}

  defp calculate_stream_statistics(stream) do
    timestamps = Enum.map(stream, fn {ts, _} -> ts end)
    values = Enum.map(stream, fn {_, val} -> val end)

    %{
      count: length(stream),
      timestamp_range:
        if(length(timestamps) > 1, do: Enum.max(timestamps) - Enum.min(timestamps), else: 0),
      value_range: if(length(values) > 1, do: Enum.max(values) - Enum.min(values), else: 0.0),
      first_timestamp: List.first(timestamps),
      last_timestamp: List.last(timestamps),
      first_value: List.first(values),
      last_value: List.last(values)
    }
  end

  # Validate characteristics of decoded stream
  defp validate_stream_characteristics(stream, stats, opts) do
    expected_count = Keyword.get(opts, :expected_count)
    max_timestamp_range = Keyword.get(opts, :max_timestamp_range)
    max_value_range = Keyword.get(opts, :max_value_range)
    min_timestamp = Keyword.get(opts, :min_timestamp)
    max_timestamp = Keyword.get(opts, :max_timestamp)

    cond do
      expected_count && stats.count != expected_count ->
        {:error, "Count mismatch: expected #{expected_count}, got #{stats.count}"}

      max_timestamp_range && stats.timestamp_range > max_timestamp_range ->
        {:error, "Timestamp range too large: #{stats.timestamp_range} > #{max_timestamp_range}"}

      max_value_range && stats.value_range > max_value_range ->
        {:error, "Value range too large: #{stats.value_range} > #{max_value_range}"}

      min_timestamp && stats.first_timestamp && stats.first_timestamp < min_timestamp ->
        {:error, "First timestamp too early: #{stats.first_timestamp} < #{min_timestamp}"}

      max_timestamp && stats.last_timestamp && stats.last_timestamp > max_timestamp ->
        {:error, "Last timestamp too late: #{stats.last_timestamp} > #{max_timestamp}"}

      not Enum.all?(stream, &valid_data_point?/1) ->
        {:error, "Invalid data points detected"}

      true ->
        :ok
    end
  end

  # Check if a data point is valid
  defp valid_data_point?({timestamp, value})
       when is_integer(timestamp) and is_number(value) do
    is_finite(value)
  end

  defp valid_data_point?(_), do: false

  # Check if a number is finite (not NaN or infinity)
  defp is_finite(x) when is_float(x) do
    not (x != x or not is_finite_float(x))
  end

  defp is_finite(x) when is_integer(x), do: true

  # Helper to check if float is finite (not infinity)
  defp is_finite_float(x) when is_float(x) do
    x > -1.7976931348623157e308 and x < 1.7976931348623157e308
  end

  @doc """
  Estimates decompression performance for given compressed data.

  ## Parameters
  - `encoded_data`: Binary data to analyze

  ## Returns
  - `{:ok, performance_info}`: Performance estimates
  - `{:error, reason}`: If analysis fails
  """
  def estimate_decompression_performance(encoded_data) when is_binary(encoded_data) do
    try do
      case get_compression_info(encoded_data) do
        {:ok, info} ->
          # Rough performance estimates based on data characteristics
          estimated_time_ms = estimate_decompression_time(info)
          estimated_memory_mb = estimate_memory_usage(info)

          performance = %{
            estimated_decompression_time_ms: estimated_time_ms,
            estimated_memory_usage_mb: estimated_memory_mb,
            data_points: info.count,
            compression_ratio:
              if(info.count > 0, do: info.total_size / (info.count * 16), else: 0.0)
          }

          {:ok, performance}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, "Performance estimation failed: #{inspect(error)}"}
    end
  end

  def estimate_decompression_performance(_), do: {:error, "Invalid input"}

  # Estimate decompression time based on data characteristics
  defp estimate_decompression_time(info) do
    # Very rough estimate: ~0.001ms per data point + overhead
    base_time = 0.1
    per_point_time = 0.001
    base_time + info.count * per_point_time
  end

  # Estimate memory usage during decompression
  defp estimate_memory_usage(info) do
    # Rough estimate: original data size + intermediate structures
    original_size_mb = info.count * 16 / (1024 * 1024)
    overhead_mb = 0.1
    original_size_mb + overhead_mb
  end
end
