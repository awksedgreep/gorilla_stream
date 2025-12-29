defmodule GorillaStream.Compression.Encoder.Metadata do
  @moduledoc """
  Metadata handling module for adding metadata to compressed data in Gorilla compression.

  This module handles the creation and serialization of metadata that describes
  the compressed data format, compression parameters, and other information
  needed for proper decompression.

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
  import Bitwise

  @doc """
  Adds metadata to packed data.

  ## Parameters
  - `packed_data`: Binary data to add metadata to
  - `metadata`: Map containing metadata information from bit packing

  ## Returns
  - Binary data with metadata header prepended
  """
  def add_metadata(packed_data, metadata) when is_binary(packed_data) and is_map(metadata) do
    # Create comprehensive metadata header
    header = create_metadata_header(packed_data, metadata)

    # Prepend header to data
    <<header::binary, packed_data::binary>>
  end

  def add_metadata(packed_data, _metadata) when is_binary(packed_data) do
    # If no metadata provided, create minimal header
    minimal_metadata = %{
      count: 0,
      total_bits: bit_size(packed_data),
      timestamp_bit_length: 0,
      value_bit_length: 0
    }

    add_metadata(packed_data, minimal_metadata)
  end

  def add_metadata(_, _), do: {:error, "Invalid input data"}

  # Create a comprehensive metadata header
  defp create_metadata_header(packed_data, metadata) do
    count = Map.get(metadata, :count, 0)
    total_bits = Map.get(metadata, :total_bits, 0)
    timestamp_bit_length = Map.get(metadata, :timestamp_bit_length, 0)
    value_bit_length = Map.get(metadata, :value_bit_length, 0)

    # Calculate checksum for integrity verification
    checksum = :erlang.crc32(packed_data)

    # Get timestamp metadata if available
    timestamp_meta = Map.get(metadata, :timestamp_metadata, %{})
    first_timestamp = Map.get(timestamp_meta, :first_timestamp, 0)
    first_delta = Map.get(timestamp_meta, :first_delta, 0)

    # Get value metadata if available
    value_meta = Map.get(metadata, :value_metadata, %{})
    first_value = Map.get(value_meta, :first_value, 0.0)
    first_value_bits = float_to_bits(first_value)

    # VM meta (optional)
    vm_meta =
      Map.get(metadata, :vm_meta, %{victoria_metrics: false, is_counter: false, scale_decimals: 0})

    vm_enabled = Map.get(vm_meta, :victoria_metrics, false)
    is_counter = Map.get(vm_meta, :is_counter, false)
    scale_decimals = Map.get(vm_meta, :scale_decimals, 0)

    # Calculate compressed data size
    compressed_size = byte_size(packed_data)

    # Estimate original size for compression ratio calculation
    original_size = estimate_original_size(count)
    compression_ratio = if original_size > 0, do: compressed_size / original_size, else: 0.0

    # Determine header version/length: keep v1 (80 bytes) unless VM features used
    emit_v2? = vm_enabled or (is_counter and scale_decimals >= 0)

    header_size = if emit_v2?, do: 84, else: 80
    creation_time = :os.system_time(:second)

    # Flags bitfield
    flags =
      0
      |> (fn f -> if vm_enabled, do: f ||| 0x1, else: f end).()
      |> (fn f -> if is_counter, do: f ||| 0x2, else: f end).()

    base = <<
      @magic_number::64,
      @version::16,
      header_size::16,
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
      flags::32
    >>

    if emit_v2? do
      <<base::binary, scale_decimals::32>>
    else
      base
    end
  end

  # Convert float to 64-bit integer representation
  defp float_to_bits(value) when is_float(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end

  defp float_to_bits(value) when is_integer(value) do
    float_to_bits(value * 1.0)
  end

  defp float_to_bits(_), do: 0

  # Estimate original data size for compression ratio calculation
  defp estimate_original_size(count) do
    # Each data point is a {timestamp, float} tuple
    # Timestamp: 8 bytes, Float: 8 bytes = 16 bytes per point
    count * 16
  end

  @doc """
  Validates metadata header format.

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
end
