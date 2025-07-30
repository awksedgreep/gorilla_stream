defmodule GorillaStream.Compression.Decoder.MetadataTest do
  use ExUnit.Case, async: true
  alias GorillaStream.Compression.Decoder.Metadata

  @magic_number 0x474F52494C4C41
  @version 1

  describe "extract_metadata/1" do
    test "extracts valid metadata from properly formatted binary" do
      # Create a valid metadata header
      data = String.duplicate("x", 100)
      checksum = :erlang.crc32(data)
      first_value_bits = float_to_bits(42.0)

      header = <<
        @magic_number::64,
        @version::16,
        # header_length
        80::16,
        # count
        10::32,
        # compressed_size
        100::32,
        # original_size (10 * 16)
        160::32,
        checksum::32,
        # first_timestamp
        1_234_567_890::64,
        # first_delta
        60::32-signed,
        first_value_bits::64,
        # timestamp_bit_length
        320::32,
        # value_bit_length
        640::32,
        # total_bits
        960::32,
        # compression_ratio
        0.625::float-64,
        # creation_time
        1_640_995_200::64,
        # flags
        0::32
      >>

      # Create data that matches compressed_size (100 bytes)
      data = String.duplicate("x", 100)
      encoded_data = header <> data <> "extra_data"

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata.version == @version
      assert metadata.count == 10
      assert metadata.compressed_size == 100
      assert metadata.original_size == 160
      assert metadata.checksum == checksum
      assert metadata.timestamp_metadata.first_timestamp == 1_234_567_890
      assert metadata.compression_ratio == 0.625
      assert metadata.timestamp_metadata.count == 10
      assert metadata.timestamp_metadata.first_timestamp == 1_234_567_890
      assert metadata.timestamp_metadata.first_delta == 60
      assert metadata.value_metadata.count == 10
      assert metadata.value_metadata.first_value == 42.0
      assert remaining_data == data
    end

    test "handles binary too small for metadata header" do
      short_binary = <<1, 2, 3, 4, 5>>

      {metadata, remaining_data} = Metadata.extract_metadata(short_binary)

      assert metadata == %{count: 0}
      assert remaining_data == short_binary
    end

    test "handles invalid magic number" do
      invalid_magic = 0x1234567890ABCDEF

      header = <<
        invalid_magic::64,
        @version::16,
        80::16,
        10::32,
        100::32,
        160::32,
        12345::32,
        1_234_567_890::64,
        60::32-signed,
        0::64,
        320::32,
        640::32,
        960::32,
        0.625::float-64,
        1_640_995_200::64,
        0::32
      >>

      data = String.duplicate("x", 100)
      encoded_data = header <> data

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata == %{count: 0}
      assert remaining_data == encoded_data
    end

    test "handles future version gracefully" do
      future_version = @version + 1

      header = <<
        @magic_number::64,
        future_version::16,
        80::16,
        10::32,
        100::32,
        160::32,
        12345::32,
        1_234_567_890::64,
        60::32-signed,
        0::64,
        320::32,
        640::32,
        960::32,
        0.625::float-64,
        1_640_995_200::64,
        0::32
      >>

      data = String.duplicate("x", 100)
      encoded_data = header <> data

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata == %{count: 0}
      assert remaining_data == encoded_data
    end

    test "handles checksum mismatch with warning flag" do
      wrong_checksum = 99999
      first_value_bits = float_to_bits(42.0)

      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        10::32,
        100::32,
        160::32,
        wrong_checksum::32,
        1_234_567_890::64,
        60::32-signed,
        first_value_bits::64,
        320::32,
        640::32,
        960::32,
        0.625::float-64,
        1_640_995_200::64,
        0::32
      >>

      data = String.duplicate("x", 100)
      encoded_data = header <> data

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata.checksum_failed == true
      assert metadata.count == 10
      assert remaining_data == data
    end

    test "handles single data point (count = 1)" do
      data = String.duplicate("x", 100)
      checksum = :erlang.crc32(data)
      first_value_bits = float_to_bits(123.45)

      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        # count = 1
        1::32,
        100::32,
        # original_size = 1 * 16
        16::32,
        checksum::32,
        1_234_567_890::64,
        # first_delta (unused for single point)
        0::32-signed,
        first_value_bits::64,
        64::32,
        64::32,
        128::32,
        6.25::float-64,
        1_640_995_200::64,
        0::32
      >>

      # Create data that matches compressed_size (100 bytes)
      data = String.duplicate("x", 100)
      encoded_data = header <> data <> "extra"

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata.count == 1
      assert metadata.timestamp_metadata.first_delta == nil
      assert metadata.value_metadata.first_value == 123.45
      assert remaining_data == data
    end

    test "handles empty compressed data" do
      checksum = :erlang.crc32("")

      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        # count = 0
        0::32,
        # compressed_size = 0
        0::32,
        # original_size = 0
        0::32,
        checksum::32,
        # first_timestamp
        0::64,
        0::32-signed,
        # first_value_bits
        0::64,
        # timestamp_bit_length
        0::32,
        # value_bit_length
        0::32,
        # total_bits
        0::32,
        0.0::float-64,
        1_640_995_200::64,
        0::32
      >>

      encoded_data = header

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata.count == 0
      assert metadata.compressed_size == 0
      assert metadata.timestamp_metadata.first_delta == nil
      assert remaining_data == ""
    end

    test "handles non-binary input" do
      {metadata, remaining_data} = Metadata.extract_metadata(12345)

      assert metadata == %{count: 0}
      assert remaining_data == <<>>
    end

    test "handles binary smaller than compressed_size" do
      first_value_bits = float_to_bits(1.0)

      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        5::32,
        # compressed_size much larger than available data
        1000::32,
        80::32,
        12345::32,
        1_234_567_890::64,
        30::32-signed,
        first_value_bits::64,
        160::32,
        320::32,
        480::32,
        12.5::float-64,
        1_640_995_200::64,
        0::32
      >>

      # Only 5 bytes, but compressed_size claims 1000
      small_data = "small"
      encoded_data = header <> small_data

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata == %{count: 0}
      assert remaining_data == encoded_data
    end

    test "handles extreme values correctly" do
      data = String.duplicate("x", 100)
      checksum = :erlang.crc32(data)
      first_value_bits = float_to_bits(:math.pi())
      max_int32 = 0x7FFFFFFF

      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        # maximum count
        max_int32::32,
        100::32,
        # calculated original_size
        max_int32 * 16::32,
        checksum::32,
        # maximum timestamp
        0x7FFFFFFFFFFFFFFF::64,
        # minimum delta
        -2_147_483_648::32-signed,
        first_value_bits::64,
        max_int32::32,
        max_int32::32,
        max_int32::32,
        # extreme compression ratio
        100.0::float-64,
        1_640_995_200::64,
        # all flags set
        0xFFFFFFFF::32
      >>

      # Create data that matches compressed_size (100 bytes)
      data = String.duplicate("x", 100)
      encoded_data = header <> data <> "padding"

      {metadata, remaining_data} = Metadata.extract_metadata(encoded_data)

      assert metadata.count == max_int32
      assert metadata.timestamp_metadata.first_timestamp == 0x7FFFFFFFFFFFFFFF
      assert metadata.timestamp_metadata.first_delta == -2_147_483_648
      assert metadata.value_metadata.first_value == :math.pi()
      assert metadata.flags == 0xFFFFFFFF
      assert remaining_data == data
    end
  end

  describe "validate_metadata_header/1" do
    test "validates correct header format" do
      header = create_valid_header()

      assert Metadata.validate_metadata_header(header) == :ok
    end

    test "rejects binary too small" do
      small_binary = <<1, 2, 3>>

      assert {:error, "Binary too small to contain valid metadata header"} =
               Metadata.validate_metadata_header(small_binary)
    end

    test "rejects invalid magic number" do
      header = <<
        # wrong magic
        0x1234567890ABCDEF::64,
        @version::16,
        80::16,
        create_dummy_header_data()::binary
      >>

      assert {:error, "Invalid magic number"} = Metadata.validate_metadata_header(header)
    end

    test "rejects unsupported version" do
      future_version = @version + 1

      header = <<
        @magic_number::64,
        # future version
        future_version::16,
        80::16,
        create_dummy_header_data()::binary
      >>

      {:error, error_message} = Metadata.validate_metadata_header(header)
      assert error_message == "Unsupported version: #{future_version}"
    end

    test "rejects invalid header length" do
      header = <<
        @magic_number::64,
        @version::16,
        # wrong header length
        32::16,
        create_dummy_header_data()::binary
      >>

      assert {:error, "Invalid header length: 32"} = Metadata.validate_metadata_header(header)
    end

    test "rejects non-binary input" do
      assert {:error, "Invalid input - not binary"} = Metadata.validate_metadata_header(123)
      assert {:error, "Invalid input - not binary"} = Metadata.validate_metadata_header(:atom)
      assert {:error, "Invalid input - not binary"} = Metadata.validate_metadata_header(nil)
    end
  end

  describe "get_header_info/1" do
    test "extracts basic info from valid header" do
      header = create_valid_header()

      {:ok, info} = Metadata.get_header_info(header)

      assert info.version == @version
      assert info.header_length == 80
      assert info.count == 10
      assert info.compressed_size == 100
      assert info.original_size == 160
      assert info.first_timestamp == 1_234_567_890
      assert info.compression_ratio == 0.625
    end

    test "handles zero original size" do
      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        5::32,
        50::32,
        # original_size = 0
        0::32,
        12345::32,
        1_234_567_890::64,
        create_dummy_remaining_header()::binary
      >>

      {:ok, info} = Metadata.get_header_info(header)

      assert info.compression_ratio == 0.0
      assert info.original_size == 0
    end

    test "returns error for invalid header" do
      invalid_header = <<1, 2, 3, 4>>

      assert {:error, "Binary too small to contain valid metadata header"} =
               Metadata.get_header_info(invalid_header)
    end

    test "rejects non-binary input" do
      assert {:error, "Invalid input - not binary"} = Metadata.get_header_info([1, 2, 3])
    end
  end

  describe "has_valid_header?/1" do
    test "returns true for valid header" do
      header = create_valid_header()

      assert Metadata.has_valid_header?(header) == true
    end

    test "returns false for invalid header" do
      invalid_header = <<1, 2, 3, 4>>

      assert Metadata.has_valid_header?(invalid_header) == false
    end

    test "returns false for non-binary input" do
      assert Metadata.has_valid_header?(123) == false
      assert Metadata.has_valid_header?(:atom) == false
      assert Metadata.has_valid_header?(nil) == false
    end
  end

  describe "estimate_original_size/1" do
    test "calculates size for given count" do
      metadata = %{count: 100}

      # 100 * 16
      assert Metadata.estimate_original_size(metadata) == 1600
    end

    test "handles zero count" do
      metadata = %{count: 0}

      assert Metadata.estimate_original_size(metadata) == 0
    end

    test "handles missing count" do
      metadata = %{}

      assert Metadata.estimate_original_size(metadata) == 0
    end

    test "handles non-map input" do
      assert Metadata.estimate_original_size("not a map") == 0
      assert Metadata.estimate_original_size(nil) == 0
    end
  end

  describe "calculate_efficiency_metrics/1" do
    test "calculates comprehensive metrics" do
      metadata = %{
        compressed_size: 100,
        original_size: 200,
        count: 10
      }

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      assert metrics.compression_ratio == 0.5
      assert metrics.space_savings == 0.5
      assert metrics.bytes_per_point == 10.0
      assert metrics.compressed_size == 100
      assert metrics.original_size == 200
      assert metrics.data_points == 10
    end

    test "handles zero original size" do
      metadata = %{
        compressed_size: 100,
        original_size: 0,
        count: 5
      }

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      assert metrics.compression_ratio == 0.0
      assert metrics.space_savings == 0.0
      assert metrics.bytes_per_point == 20.0
    end

    test "handles zero count" do
      metadata = %{
        compressed_size: 100,
        original_size: 200,
        count: 0
      }

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      assert metrics.compression_ratio == 0.5
      assert metrics.space_savings == 0.5
      assert metrics.bytes_per_point == 0.0
    end

    test "uses estimated original size when missing" do
      metadata = %{
        compressed_size: 80,
        count: 5
        # original_size missing
      }

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      # estimated
      expected_original_size = 5 * 16
      assert metrics.original_size == expected_original_size
      assert metrics.compression_ratio == 80 / expected_original_size
      assert metrics.space_savings == (expected_original_size - 80) / expected_original_size
    end

    test "handles completely empty metadata" do
      metadata = %{}

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      assert metrics.compression_ratio == 0.0
      assert metrics.space_savings == 0.0
      assert metrics.bytes_per_point == 0.0
      assert metrics.compressed_size == 0
      assert metrics.original_size == 0
      assert metrics.data_points == 0
    end

    test "handles extreme compression ratios" do
      metadata = %{
        compressed_size: 1,
        original_size: 10000,
        count: 625
      }

      metrics = Metadata.calculate_efficiency_metrics(metadata)

      assert metrics.compression_ratio == 0.0001
      assert metrics.space_savings == 0.9999
      assert metrics.bytes_per_point == 1.0 / 625
    end
  end

  # Helper functions
  defp create_valid_header do
    checksum = :erlang.crc32("test")

    <<
      @magic_number::64,
      @version::16,
      80::16,
      10::32,
      100::32,
      160::32,
      checksum::32,
      1_234_567_890::64,
      30::32-signed,
      float_to_bits(42.0)::64,
      320::32,
      640::32,
      960::32,
      0.625::float-64,
      1_640_995_200::64,
      0::32
    >>
  end

  defp create_dummy_header_data do
    <<
      10::32,
      100::32,
      160::32,
      12345::32,
      1_234_567_890::64,
      30::32-signed,
      0::64,
      320::32,
      640::32,
      960::32,
      0.625::float-64,
      1_640_995_200::64,
      0::32
    >>
  end

  defp create_dummy_remaining_header do
    <<
      30::32-signed,
      0::64,
      320::32,
      640::32,
      960::32,
      0.625::float-64,
      1_640_995_200::64,
      0::32
    >>
  end

  defp float_to_bits(value) do
    <<bits::64>> = <<value::float-64>>
    bits
  end
end
