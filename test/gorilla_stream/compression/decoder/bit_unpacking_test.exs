defmodule GorillaStream.Compression.Decoder.BitUnpackingTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Decoder.BitUnpacking
  alias GorillaStream.Compression.Encoder.BitPacking
  alias GorillaStream.Compression.Encoder.DeltaEncoding
  alias GorillaStream.Compression.Encoder.ValueCompression

  describe "unpack/1" do
    test "unpacks empty data" do
      assert {<<>>, <<>>, %{count: 0}} = BitUnpacking.unpack(<<>>)
    end

    test "unpacks single timestamp data" do
      timestamps = [1000]
      values = [42.0]

      # Create encoded bitstreams
      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)

      # Pack them together
      {packed_data, _metadata} = BitPacking.pack(timestamp_result, value_result)

      # Unpack and verify
      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 1
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 42.0
      assert bit_size(unpacked_timestamp_bits) >= 0
      assert bit_size(unpacked_value_bits) >= 0
    end

    test "unpacks two timestamp data" do
      timestamps = [1000, 1010]
      values = [42.0, 43.0]

      # Create encoded bitstreams
      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)

      # Pack them together
      {packed_data, _metadata} = BitPacking.pack(timestamp_result, value_result)

      # Unpack and verify
      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 2
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 42.0
    end

    test "unpacks multiple timestamps and values" do
      timestamps = [1000, 1010, 1020, 1015, 1025]
      values = [42.0, 43.0, 44.0, 43.5, 44.5]

      # Create encoded bitstreams
      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)

      # Pack them together
      {packed_data, _metadata} = BitPacking.pack(timestamp_result, value_result)

      # Unpack and verify
      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 5
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 42.0
      assert is_bitstring(unpacked_timestamp_bits)
      assert is_bitstring(unpacked_value_bits)
    end

    test "unpacks data with large timestamps" do
      large_timestamp = 1_000_000_000_000
      timestamps = [large_timestamp, large_timestamp + 1000]
      values = [100.0, 200.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 2
      assert metadata.timestamp_metadata.first_timestamp == large_timestamp
      assert metadata.value_metadata.first_value == 100.0
    end

    test "unpacks data with negative values" do
      timestamps = [1000, 2000, 3000]
      values = [-10.0, -20.0, -30.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 3
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == -10.0
    end

    test "unpacks data with zero values" do
      timestamps = [1000, 2000]
      values = [0.0, 0.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 2
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 0.0
    end

    test "unpacks data with identical values" do
      timestamps = [1000, 2000, 3000, 4000]
      values = [42.0, 42.0, 42.0, 42.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 4
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 42.0
    end

    test "unpacks data with varying timestamp deltas" do
      timestamps = [1000, 1005, 1015, 1020, 1040]
      values = [1.0, 2.0, 3.0, 4.0, 5.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 5
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 1.0
      assert metadata.timestamp_metadata.first_delta == 5
    end

    test "unpacks large dataset" do
      # Generate larger dataset
      timestamps = for i <- 1..50, do: 1000 + i * 10
      values = for i <- 1..50, do: i * 1.5

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 50
      assert metadata.timestamp_metadata.first_timestamp == 1010
      assert metadata.value_metadata.first_value == 1.5
      assert bit_size(unpacked_timestamp_bits) > 0
      assert bit_size(unpacked_value_bits) > 0
    end

    test "unpacks high precision floating point values" do
      timestamps = [1000, 2000, 3000]
      values = [3.141592653589793, 2.718281828459045, 1.4142135623730951]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, metadata} =
        BitUnpacking.unpack(packed_data)

      assert metadata.count == 3
      assert metadata.timestamp_metadata.first_timestamp == 1000
      assert metadata.value_metadata.first_value == 3.141592653589793
    end
  end

  describe "error conditions and edge cases" do
    test "handles insufficient data for header" do
      # Less than 32 bytes needed for header
      insufficient_data = <<1, 2, 3, 4, 5>>

      assert {<<>>, <<>>, %{count: 0}} = BitUnpacking.unpack(insufficient_data)
    end

    test "handles invalid input types" do
      assert {<<>>, <<>>, %{count: 0}} = BitUnpacking.unpack("not binary")
      assert {<<>>, <<>>, %{count: 0}} = BitUnpacking.unpack(123)
      assert {<<>>, <<>>, %{count: 0}} = BitUnpacking.unpack(nil)
    end

    test "handles corrupted header data" do
      # Create 32 bytes of potentially invalid header data
      corrupted_header = :crypto.strong_rand_bytes(32)

      # Should return empty results for corrupted data
      result = BitUnpacking.unpack(corrupted_header)

      case result do
        {<<>>, <<>>, %{count: 0}} -> :ok
        {_ts, _vs, metadata} when is_map(metadata) -> :ok
      end
    end

    test "handles data with zero bit lengths" do
      # Create a header that indicates zero-length bitstreams
      header = <<
        # count
        2::32,
        # first_timestamp
        1000::64,
        # first_value_bits (0.0)
        0::64,
        # first_delta
        10::32-signed,
        # timestamp_bits_len
        0::32,
        # value_bits_len
        0::32
      >>

      {timestamp_bits, value_bits, metadata} = BitUnpacking.unpack(header)

      assert metadata.count == 2
      assert timestamp_bits == <<>>
      assert value_bits == <<>>
    end

    test "handles truncated bitstream data" do
      # Create a valid header but insufficient bitstream data
      header = <<
        # count
        2::32,
        # first_timestamp
        1000::64,
        # first_value_bits
        0::64,
        # first_delta
        10::32-signed,
        # timestamp_bits_len (need 2 bytes)
        16::32,
        # value_bits_len (need 2 bytes)
        16::32,
        # Only 1 byte instead of 4 needed
        1::8
      >>

      result = BitUnpacking.unpack(header)

      # Should handle gracefully
      case result do
        {<<>>, <<>>, %{count: 0}} -> :ok
        {_ts, _vs, _metadata} -> :ok
      end
    end

    test "handles very large bit lengths" do
      # Create header with unreasonably large bit lengths
      header = <<
        # count
        2::32,
        # first_timestamp
        1000::64,
        # first_value_bits
        0::64,
        # first_delta
        10::32-signed,
        # timestamp_bits_len
        1_000_000::32,
        # value_bits_len
        1_000_000::32
      >>

      result = BitUnpacking.unpack(header)

      # Should handle gracefully without crashing
      case result do
        {<<>>, <<>>, %{count: 0}} -> :ok
        {_ts, _vs, _metadata} -> :ok
      end
    end

    test "preserves metadata fields correctly" do
      timestamps = [5000, 5100, 5200]
      values = [99.9, 88.8, 77.7]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, original_metadata} = BitPacking.pack(timestamp_result, value_result)

      {_unpacked_timestamp_bits, _unpacked_value_bits, unpacked_metadata} =
        BitUnpacking.unpack(packed_data)

      # Verify key metadata fields are preserved
      assert unpacked_metadata.count == original_metadata.count

      assert unpacked_metadata.timestamp_metadata.first_timestamp ==
               original_metadata.timestamp_metadata.first_timestamp

      assert unpacked_metadata.value_metadata.first_value ==
               original_metadata.value_metadata.first_value
    end
  end

  describe "round-trip consistency" do
    test "maintains bit-level consistency through pack/unpack cycle" do
      timestamps = [1000, 1005, 1012, 1018, 1030]
      values = [10.5, 20.7, 15.3, 25.9, 30.1]

      # Encode original data
      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {original_timestamp_bits, _} = timestamp_result
      {original_value_bits, _} = value_result

      # Pack and then unpack
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)
      {unpacked_timestamp_bits, unpacked_value_bits, _metadata} = BitUnpacking.unpack(packed_data)

      # The unpacked bits should match the original encoded bits
      assert unpacked_timestamp_bits == original_timestamp_bits
      assert unpacked_value_bits == original_value_bits
    end

    test "handles empty bitstreams in round-trip" do
      # Test with minimal data that produces small bitstreams
      timestamps = [1000]
      values = [42.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)

      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)
      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 1
      assert is_bitstring(unpacked_timestamp_bits)
      assert is_bitstring(unpacked_value_bits)
    end

    test "preserves exact bit patterns for various data patterns" do
      test_cases = [
        # Regular increasing pattern
        {[1000, 1010, 1020, 1030], [1.0, 2.0, 3.0, 4.0]},
        # Irregular pattern
        {[1000, 1005, 1025, 1027], [10.0, 15.0, 5.0, 20.0]},
        # Repeated values
        {[1000, 2000, 3000], [42.0, 42.0, 42.0]},
        # Negative deltas
        {[1000, 950, 900, 925], [1.0, 2.0, 3.0, 4.0]}
      ]

      for {timestamps, values} <- test_cases do
        timestamp_result = DeltaEncoding.encode(timestamps)
        value_result = ValueCompression.compress(values)
        {original_timestamp_bits, _} = timestamp_result
        {original_value_bits, _} = value_result

        {packed_data, _} = BitPacking.pack(timestamp_result, value_result)
        {unpacked_timestamp_bits, unpacked_value_bits, _} = BitUnpacking.unpack(packed_data)

        assert unpacked_timestamp_bits == original_timestamp_bits,
               "Timestamp bits mismatch for pattern #{inspect(timestamps)}"

        assert unpacked_value_bits == original_value_bits,
               "Value bits mismatch for pattern #{inspect(values)}"
      end
    end
  end

  describe "validate_packed_data/1" do
    test "validates correctly packed data" do
      timestamps = [1000, 1010, 1020]
      values = [42.0, 43.0, 44.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      assert :ok = BitUnpacking.validate_packed_data(packed_data)
    end

    test "validates empty packed data" do
      assert :ok = BitUnpacking.validate_packed_data(<<>>)
    end

    test "handles insufficient data" do
      short_data = <<1, 2, 3, 4, 5>>
      assert :ok = BitUnpacking.validate_packed_data(short_data)
    end

    test "rejects non-binary input" do
      assert {:error, "Invalid input - expected binary data"} =
               BitUnpacking.validate_packed_data(123)

      assert {:error, "Invalid input - expected binary data"} =
               BitUnpacking.validate_packed_data(:atom)
    end

    test "handles corrupted data gracefully" do
      corrupted_data = :crypto.strong_rand_bytes(50)

      result = BitUnpacking.validate_packed_data(corrupted_data)

      case result do
        :ok -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "get_packed_info/1" do
    test "extracts info from valid packed data" do
      timestamps = [1000, 1010, 1020, 1030]
      values = [10.0, 20.0, 30.0, 40.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      assert {:ok, info} = BitUnpacking.get_packed_info(packed_data)

      assert info.total_size == byte_size(packed_data)
      assert info.header_size == 32
      assert info.count == 4
      assert info.first_timestamp == 1000
      assert info.first_value == 10.0
      assert info.first_delta == 10
      assert info.timestamp_bit_length >= 0
      assert info.value_bit_length >= 0
    end

    test "handles empty data" do
      assert {:error, "Data too small for valid header"} =
               BitUnpacking.get_packed_info(<<>>)
    end

    test "rejects non-binary input" do
      assert {:error, "Invalid input - expected binary data"} =
               BitUnpacking.get_packed_info(123)
    end

    test "handles corrupted header gracefully" do
      corrupted_data = :crypto.strong_rand_bytes(40)

      result = BitUnpacking.get_packed_info(corrupted_data)

      case result do
        {:ok, _info} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "estimate_unpacking_performance/1" do
    test "estimates performance for typical data" do
      timestamps = [1000, 1010, 1020, 1030, 1040]
      values = [10.0, 15.0, 20.0, 25.0, 30.0]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      assert {:ok, performance} = BitUnpacking.estimate_unpacking_performance(packed_data)

      assert performance.data_points == 5
      assert performance.estimated_unpacking_time_ms > 0
      assert performance.estimated_memory_usage_kb > 0
      assert performance.bitstream_efficiency >= 0.0
      assert performance.bitstream_efficiency <= 1.0
    end

    test "handles empty data" do
      assert {:error, "Data too small for valid header"} =
               BitUnpacking.estimate_unpacking_performance(<<>>)
    end

    test "rejects non-binary input" do
      assert {:error, "Invalid input"} =
               BitUnpacking.estimate_unpacking_performance(123)
    end

    test "handles corrupted data gracefully" do
      corrupted_data = :crypto.strong_rand_bytes(50)

      result = BitUnpacking.estimate_unpacking_performance(corrupted_data)

      case result do
        {:ok, _performance} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "performance and stress testing" do
    test "handles very large datasets efficiently" do
      # Generate large dataset
      timestamps = for i <- 1..1000, do: 1000 + i * 5
      values = for i <- 1..1000, do: :math.sin(i * 0.1) * 100

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 1000
      assert metadata.timestamp_metadata.first_timestamp == 1005
      assert is_bitstring(unpacked_timestamp_bits)
      assert is_bitstring(unpacked_value_bits)
      assert bit_size(unpacked_timestamp_bits) > 0
      assert bit_size(unpacked_value_bits) > 0
    end

    test "handles minimal datasets correctly" do
      # Single data point
      timestamps = [42]
      values = [3.14]

      timestamp_result = DeltaEncoding.encode(timestamps)
      value_result = ValueCompression.compress(values)
      {packed_data, _} = BitPacking.pack(timestamp_result, value_result)

      {unpacked_timestamp_bits, unpacked_value_bits, metadata} = BitUnpacking.unpack(packed_data)

      assert metadata.count == 1
      assert metadata.timestamp_metadata.first_timestamp == 42
      assert metadata.value_metadata.first_value == 3.14
      assert is_bitstring(unpacked_timestamp_bits)
      assert is_bitstring(unpacked_value_bits)
    end
  end
end
