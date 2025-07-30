defmodule GorillaStream.Compression.Encoder.MetadataTest do
  use ExUnit.Case, async: true
  alias GorillaStream.Compression.Encoder.Metadata

  @magic_number 0x474F52494C4C41
  @version 1

  describe "add_metadata/2" do
    test "adds comprehensive metadata to packed data" do
      packed_data = "test_compressed_data"

      metadata = %{
        count: 10,
        total_bits: 800,
        timestamp_bit_length: 320,
        value_bit_length: 480,
        timestamp_metadata: %{
          first_timestamp: 1_234_567_890,
          first_delta: 60
        },
        value_metadata: %{
          first_value: 42.5
        }
      }

      result = Metadata.add_metadata(packed_data, metadata)

      # Should be header (80 bytes) + packed_data
      assert byte_size(result) == 80 + byte_size(packed_data)

      # Extract header
      <<header::binary-size(80), remaining_data::binary>> = result

      # Verify magic number and version
      <<magic::64, version::16, _rest::binary>> = header
      assert magic == @magic_number
      assert version == @version
      assert remaining_data == packed_data
    end

    test "handles metadata with missing optional fields" do
      packed_data = "minimal_data"

      metadata = %{
        count: 5
      }

      result = Metadata.add_metadata(packed_data, metadata)

      assert byte_size(result) == 80 + byte_size(packed_data)

      # Verify it still creates valid header structure
      <<header::binary-size(80), remaining_data::binary>> = result
      <<magic::64, version::16, header_length::16, count::32, _rest::binary>> = header

      assert magic == @magic_number
      assert version == @version
      assert header_length == 80
      assert count == 5
      assert remaining_data == packed_data
    end

    test "creates minimal header when no metadata provided" do
      packed_data = "some_data"

      result = Metadata.add_metadata(packed_data, %{})

      assert byte_size(result) == 80 + byte_size(packed_data)

      <<header::binary-size(80), remaining_data::binary>> = result
      <<magic::64, version::16, _header_length::16, count::32, _rest::binary>> = header

      assert magic == @magic_number
      assert version == @version
      assert count == 0
      assert remaining_data == packed_data
    end

    test "handles empty packed data" do
      packed_data = ""

      metadata = %{
        count: 0,
        total_bits: 0
      }

      result = Metadata.add_metadata(packed_data, metadata)

      assert byte_size(result) == 80

      <<header::binary-size(80)>> = result

      <<magic::64, version::16, _header_length::16, count::32, compressed_size::32,
        _rest::binary>> = header

      assert magic == @magic_number
      assert version == @version
      assert count == 0
      assert compressed_size == 0
    end

    test "handles large datasets with extreme values" do
      packed_data = String.duplicate("x", 1000)

      metadata = %{
        count: 1_000_000,
        total_bits: 64_000_000,
        timestamp_bit_length: 32_000_000,
        value_bit_length: 32_000_000,
        timestamp_metadata: %{
          first_timestamp: 0x7FFFFFFFFFFFFFFF,
          first_delta: -2_147_483_648
        },
        value_metadata: %{
          first_value: :math.pi()
        }
      }

      result = Metadata.add_metadata(packed_data, metadata)

      assert byte_size(result) == 80 + 1000

      <<header::binary-size(80), remaining_data::binary>> = result

      <<magic::64, _version::16, _header_length::16, count::32, compressed_size::32,
        original_size::32, checksum::32, first_timestamp::64, first_delta::32-signed,
        _rest::binary>> = header

      assert magic == @magic_number
      assert count == 1_000_000
      assert compressed_size == 1000
      assert original_size == 1_000_000 * 16
      assert first_timestamp == 0x7FFFFFFFFFFFFFFF
      assert first_delta == -2_147_483_648
      assert remaining_data == packed_data

      # Verify checksum
      expected_checksum = :erlang.crc32(packed_data)
      assert checksum == expected_checksum
    end

    test "calculates checksum correctly" do
      packed_data = "checksum_test_data"
      expected_checksum = :erlang.crc32(packed_data)

      metadata = %{count: 1}

      result = Metadata.add_metadata(packed_data, metadata)

      <<_magic::64, _version::16, _header_length::16, _count::32, _compressed_size::32,
        _original_size::32, checksum::32, _rest::binary>> = result

      assert checksum == expected_checksum
    end

    test "handles float values correctly" do
      packed_data = "float_test"

      metadata = %{
        count: 3,
        value_metadata: %{
          first_value: 123.456
        }
      }

      result = Metadata.add_metadata(packed_data, metadata)

      <<_header_prefix::binary-size(40), first_value_bits::64, _rest::binary>> = result

      # Convert back to float and verify
      <<reconstructed_value::float-64>> = <<first_value_bits::64>>
      assert reconstructed_value == 123.456
    end

    test "handles integer values in value_metadata" do
      packed_data = "integer_test"

      metadata = %{
        count: 2,
        value_metadata: %{
          first_value: 42
        }
      }

      result = Metadata.add_metadata(packed_data, metadata)

      <<_header_prefix::binary-size(40), first_value_bits::64, _rest::binary>> = result

      # Should convert integer to float
      <<reconstructed_value::float-64>> = <<first_value_bits::64>>
      assert reconstructed_value == 42.0
    end

    test "handles invalid first_value gracefully" do
      packed_data = "invalid_value_test"

      metadata = %{
        count: 1,
        value_metadata: %{
          first_value: "not_a_number"
        }
      }

      result = Metadata.add_metadata(packed_data, metadata)

      <<_header_prefix::binary-size(40), first_value_bits::64, _rest::binary>> = result

      # Should default to 0.0
      <<reconstructed_value::float-64>> = <<first_value_bits::64>>
      assert reconstructed_value == 0.0
    end

    test "calculates compression ratio correctly" do
      packed_data = String.duplicate("x", 50)

      metadata = %{
        # Original size would be 10 * 16 = 160 bytes
        count: 10
      }

      result = Metadata.add_metadata(packed_data, metadata)

      <<_header_prefix::binary-size(60), compression_ratio::float-64, _rest::binary>> = result

      # Compression ratio should be 50/160 = 0.3125
      expected_ratio = 50.0 / 160.0
      assert compression_ratio == expected_ratio
    end

    test "handles zero count for compression ratio" do
      packed_data = "zero_count_test"

      metadata = %{
        count: 0
      }

      result = Metadata.add_metadata(packed_data, metadata)

      <<_header_prefix::binary-size(60), compression_ratio::float-64, _rest::binary>> = result

      # Should be 0.0 when original size is 0
      assert compression_ratio == 0.0
    end

    test "includes creation timestamp in reasonable range" do
      packed_data = "timestamp_test"
      metadata = %{count: 1}

      before_time = :os.system_time(:second)
      result = Metadata.add_metadata(packed_data, metadata)
      after_time = :os.system_time(:second)

      <<_header_prefix::binary-size(68), creation_time::64, _rest::binary>> = result

      # Creation time should be between before and after
      assert creation_time >= before_time
      assert creation_time <= after_time
    end

    test "returns error for non-binary packed data" do
      assert Metadata.add_metadata(123, %{}) == {:error, "Invalid input data"}
      assert Metadata.add_metadata(:atom, %{}) == {:error, "Invalid input data"}
      assert Metadata.add_metadata(nil, %{}) == {:error, "Invalid input data"}
    end

    test "handles non-map metadata by creating minimal metadata" do
      packed_data = "non_map_metadata"

      result = Metadata.add_metadata(packed_data, "not_a_map")

      assert byte_size(result) == 80 + byte_size(packed_data)

      <<header::binary-size(80), remaining_data::binary>> = result
      <<magic::64, version::16, _header_length::16, count::32, _rest::binary>> = header

      assert magic == @magic_number
      assert version == @version
      assert count == 0
      assert remaining_data == packed_data
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

    test "calculates compression ratio correctly" do
      header = <<
        @magic_number::64,
        @version::16,
        80::16,
        # count = 4
        4::32,
        # compressed_size = 32
        32::32,
        # original_size = 4 * 16 = 64
        64::32,
        12345::32,
        1_234_567_890::64,
        create_dummy_remaining_header()::binary
      >>

      {:ok, info} = Metadata.get_header_info(header)

      # 32/64 = 0.5
      assert info.compression_ratio == 0.5
    end
  end

  describe "integration with actual compression pipeline" do
    test "round-trip metadata consistency" do
      original_metadata = %{
        count: 42,
        total_bits: 2688,
        timestamp_bit_length: 1344,
        value_bit_length: 1344,
        timestamp_metadata: %{
          first_timestamp: 1_640_995_200,
          first_delta: 30
        },
        value_metadata: %{
          first_value: 98.6
        }
      }

      packed_data = "integration_test_data"

      # Add metadata
      with_metadata = Metadata.add_metadata(packed_data, original_metadata)

      # Extract header info
      {:ok, extracted_info} = Metadata.get_header_info(with_metadata)

      # Verify key fields match
      assert extracted_info.count == original_metadata.count

      assert extracted_info.first_timestamp ==
               original_metadata.timestamp_metadata.first_timestamp

      # Verify data integrity
      <<_header::binary-size(80), extracted_data::binary>> = with_metadata
      assert extracted_data == packed_data
    end

    test "handles edge case with maximum values" do
      max_count = 0x7FFFFFFF

      metadata = %{
        count: max_count,
        total_bits: max_count,
        timestamp_bit_length: max_count,
        value_bit_length: max_count,
        timestamp_metadata: %{
          first_timestamp: 0x7FFFFFFFFFFFFFFF,
          first_delta: -2_147_483_648
        },
        value_metadata: %{
          # Close to max float64
          first_value: 1.7976931348623157e308
        }
      }

      packed_data = String.duplicate("max", 1000)

      result = Metadata.add_metadata(packed_data, metadata)
      {:ok, info} = Metadata.get_header_info(result)

      assert info.count == max_count
      assert info.first_timestamp == 0x7FFFFFFFFFFFFFFF
    end

    test "metadata size calculation is consistent" do
      test_data = "consistency_test"
      metadata = %{count: 5, total_bits: 320}

      result = Metadata.add_metadata(test_data, metadata)

      # Header should always be 80 bytes
      assert byte_size(result) == 80 + byte_size(test_data)

      {:ok, info} = Metadata.get_header_info(result)
      assert info.header_length == 80
      assert info.compressed_size == byte_size(test_data)
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
