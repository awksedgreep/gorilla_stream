defmodule GorillaStream.Compression.Decoder.DeltaDecodingTest do
  use ExUnit.Case, async: true
  alias GorillaStream.Compression.Decoder.DeltaDecoding

  describe "decode/2" do
    test "handles empty bitstream with count 0" do
      assert {:ok, []} = DeltaDecoding.decode(<<>>, %{count: 0})
    end

    test "decodes single timestamp correctly" do
      timestamp = 1_609_459_200
      bitstream = <<timestamp::64>>
      metadata = %{count: 1, first_timestamp: timestamp}

      assert {:ok, [^timestamp]} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes two timestamps with simple delta" do
      first_timestamp = 1_609_459_200
      first_delta = 1
      # Format: first_timestamp + first_delta_encoding
      bitstream = <<first_timestamp::64, 1::1, 0::1, first_delta::7-signed>>

      metadata = %{
        count: 2,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [first_timestamp, first_timestamp + 1]
      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes regular time series with zero delta-of-deltas" do
      first_timestamp = 1_609_459_200
      first_delta = 1
      # Format: first_timestamp + first_delta + three zero delta-of-deltas
      bitstream = <<
        first_timestamp::64,
        # first delta = 1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 0
        0::1,
        # delta-of-delta = 0
        0::1,
        # delta-of-delta = 0
        0::1
      >>

      metadata = %{
        count: 5,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        first_timestamp,
        first_timestamp + 1,
        first_timestamp + 2,
        first_timestamp + 3,
        first_timestamp + 4
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes timestamps with varying delta-of-deltas" do
      first_timestamp = 1_609_459_200
      first_delta = 1
      # deltas: 1, 2, 1 -> delta-of-deltas: 1, -1
      bitstream = <<
        first_timestamp::64,
        # first delta = 1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 1 (new delta = 2)
        1::1,
        0::1,
        1::7-signed,
        # delta-of-delta = -1 (new delta = 1)
        1::1,
        0::1,
        -1::7-signed
      >>

      metadata = %{
        count: 4,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459201 (delta=1)
        first_timestamp + 1,
        # 1609459203 (delta=2)
        first_timestamp + 3,
        # 1609459204 (delta=1)
        first_timestamp + 4
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes negative deltas correctly" do
      first_timestamp = 1_609_459_200
      first_delta = -1

      bitstream = <<
        first_timestamp::64,
        # first delta = -1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 0
        0::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459199
        first_timestamp - 1,
        # 1609459198
        first_timestamp - 2
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes zero first delta" do
      first_timestamp = 1_609_459_200
      first_delta = 0

      bitstream = <<
        first_timestamp::64,
        # first delta = 0
        0::1,
        # delta-of-delta = 0
        0::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459200 (same)
        first_timestamp,
        # 1609459200 (same)
        first_timestamp
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes large deltas requiring 9-bit encoding" do
      first_timestamp = 1_609_459_200
      first_delta = 100

      bitstream = <<
        first_timestamp::64,
        # first delta = 100 (9-bit)
        1::1,
        1::1,
        0::1,
        first_delta::9-signed,
        # delta-of-delta = 50 (new delta = 150)
        1::1,
        0::1,
        50::7-signed
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459300
        first_timestamp + 100,
        # 1609459450
        first_timestamp + 250
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes very large deltas requiring 12-bit encoding" do
      first_timestamp = 1_609_459_200
      first_delta = 1000

      bitstream = <<
        first_timestamp::64,
        # first delta = 1000 (12-bit)
        1::1,
        1::1,
        1::1,
        0::1,
        first_delta::12-signed,
        # delta-of-delta = 0
        0::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609460200
        first_timestamp + 1000,
        # 1609461200
        first_timestamp + 2000
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "decodes maximum deltas requiring 32-bit encoding" do
      first_timestamp = 1_609_459_200
      first_delta = 100_000

      bitstream = <<
        first_timestamp::64,
        # first delta = 100000 (32-bit)
        1::1,
        1::1,
        1::1,
        1::1,
        first_delta::32-signed,
        # delta-of-delta = 0
        0::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609559200
        first_timestamp + 100_000,
        # 1609659200
        first_timestamp + 200_000
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles boundary values for delta-of-delta encoding" do
      first_timestamp = 1_609_459_200
      first_delta = 1

      # Test delta-of-delta at 7-bit boundary (63)
      bitstream = <<
        first_timestamp::64,
        # first delta = 1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 63 (fits in 7 bits)
        1::1,
        0::1,
        63::7-signed
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459201 (delta=1)
        first_timestamp + 1,
        # 1609459265 (delta=64)
        first_timestamp + 65
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles delta-of-delta requiring 9-bit encoding" do
      first_timestamp = 1_609_459_200
      first_delta = 1

      # Test delta-of-delta requiring 9 bits (200)
      bitstream = <<
        first_timestamp::64,
        # first delta = 1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 200 (needs 9 bits)
        1::1,
        1::1,
        0::1,
        200::9-signed
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459201 (delta=1)
        first_timestamp + 1,
        # 1609459402 (delta=201)
        first_timestamp + 202
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles negative delta-of-deltas" do
      first_timestamp = 1_609_459_200
      first_delta = 10

      # deltas: 10, 5 -> delta-of-delta: -5
      bitstream = <<
        first_timestamp::64,
        # first delta = 10
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = -5
        1::1,
        0::1,
        -5::7-signed
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459210 (delta=10)
        first_timestamp + 10,
        # 1609459215 (delta=5)
        first_timestamp + 15
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "returns error for invalid input types" do
      # String is a bitstring in Elixir, and empty metadata defaults count to 0
      # So this returns {:ok, []}
      assert {:ok, []} = DeltaDecoding.decode("not bitstring", %{})

      # Non-map metadata is an error
      assert {:error, "Invalid input - expected bitstring and metadata"} =
               DeltaDecoding.decode(<<>>, "not map")
    end

    test "handles insufficient data gracefully" do
      # Truncated bitstream
      # Missing data
      bitstream = <<1_609_459_200::64, 1::1>>
      metadata = %{count: 3, first_timestamp: 1_609_459_200, first_delta: 1}

      assert {:error, _reason} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles corrupted delta-of-delta data" do
      first_timestamp = 1_609_459_200
      first_delta = 1
      # Incomplete delta-of-delta
      bitstream = <<
        first_timestamp::64,
        1::1,
        0::1,
        first_delta::7-signed,
        # Incomplete control bits
        1::1,
        1::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      assert {:error, _reason} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles edge case with maximum timestamp values" do
      max_timestamp = 4_000_000_000
      first_delta = 1

      bitstream = <<
        max_timestamp::64,
        1::1,
        0::1,
        first_delta::7-signed,
        0::1
      >>

      metadata = %{
        count: 3,
        first_timestamp: max_timestamp,
        first_delta: first_delta
      }

      expected = [
        max_timestamp,
        max_timestamp + 1,
        max_timestamp + 2
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "reconstructs complex timestamp pattern correctly" do
      first_timestamp = 1_609_459_200
      first_delta = 5
      # Pattern: deltas 5, 3, 8, 2 -> delta-of-deltas: -2, 5, -6
      bitstream = <<
        first_timestamp::64,
        # first delta = 5
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = -2 (delta=3)
        1::1,
        0::1,
        -2::7-signed,
        # delta-of-delta = 5 (delta=8)
        1::1,
        0::1,
        5::7-signed,
        # delta-of-delta = -6 (delta=2)
        1::1,
        0::1,
        -6::7-signed
      >>

      metadata = %{
        count: 5,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459205 (delta=5)
        first_timestamp + 5,
        # 1609459208 (delta=3)
        first_timestamp + 8,
        # 1609459216 (delta=8)
        first_timestamp + 16,
        # 1609459218 (delta=2)
        first_timestamp + 18
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end

    test "handles alternating delta pattern efficiently" do
      first_timestamp = 1_609_459_200
      first_delta = 1
      # Alternating deltas: 1, 2, 1, 2 -> delta-of-deltas: 1, -1, 1
      bitstream = <<
        first_timestamp::64,
        # first delta = 1
        1::1,
        0::1,
        first_delta::7-signed,
        # delta-of-delta = 1 (delta=2)
        1::1,
        0::1,
        1::7-signed,
        # delta-of-delta = -1 (delta=1)
        1::1,
        0::1,
        -1::7-signed,
        # delta-of-delta = 1 (delta=2)
        1::1,
        0::1,
        1::7-signed
      >>

      metadata = %{
        count: 5,
        first_timestamp: first_timestamp,
        first_delta: first_delta
      }

      expected = [
        # 1609459200
        first_timestamp,
        # 1609459201 (delta=1)
        first_timestamp + 1,
        # 1609459203 (delta=2)
        first_timestamp + 3,
        # 1609459204 (delta=1)
        first_timestamp + 4,
        # 1609459206 (delta=2)
        first_timestamp + 6
      ]

      assert {:ok, ^expected} = DeltaDecoding.decode(bitstream, metadata)
    end
  end

  describe "validate_bitstream/2" do
    test "validates correct bitstream" do
      bitstream = <<1_609_459_200::64, 0::1>>
      assert :ok = DeltaDecoding.validate_bitstream(bitstream, 2)
    end

    test "rejects invalid bitstream" do
      # Too small
      bitstream = <<1::1>>
      assert {:error, _} = DeltaDecoding.validate_bitstream(bitstream, 5)
    end

    test "rejects non-bitstring input" do
      # Note: Strings ARE bitstrings in Elixir
      # Without proper validation headers, the decoder will interpret any binary as timestamp data
      # This test should really be testing non-bitstring types like atoms or integers
      assert {:error, "Invalid input - expected bitstring"} =
               DeltaDecoding.validate_bitstream(:not_a_bitstring, 2)

      assert {:error, "Invalid input - expected bitstring"} =
               DeltaDecoding.validate_bitstream(123, 2)
    end
  end

  describe "get_bitstream_info/2" do
    test "returns info for empty bitstream" do
      assert {:ok, info} = DeltaDecoding.get_bitstream_info(<<>>, %{count: 0})
      assert info.count == 0
      assert info.first_timestamp == nil
    end

    test "returns info for single timestamp" do
      timestamp = 1_609_459_200
      bitstream = <<timestamp::64>>
      metadata = %{count: 1, first_timestamp: timestamp}

      assert {:ok, info} = DeltaDecoding.get_bitstream_info(bitstream, metadata)
      assert info.count == 1
      assert info.first_timestamp == timestamp
      assert info.estimated_range == 0
    end

    test "returns info for multiple timestamps" do
      first_timestamp = 1_609_459_200
      first_delta = 10
      bitstream = <<first_timestamp::64, 1::1, 0::1, first_delta::7-signed>>
      metadata = %{count: 5, first_timestamp: first_timestamp, first_delta: first_delta}

      assert {:ok, info} = DeltaDecoding.get_bitstream_info(bitstream, metadata)
      assert info.count == 5
      assert info.first_timestamp == first_timestamp
      assert info.first_delta == first_delta
      # Estimated range for 5 points with delta 10 = 4 * 10 = 40
      assert info.estimated_range == 40
    end

    test "handles invalid input gracefully" do
      assert {:error, "Invalid input"} =
               DeltaDecoding.get_bitstream_info("not bitstring", %{})
    end
  end

  describe "error conditions and edge cases" do
    test "decode/2 handles all first delta encoding formats" do
      first_timestamp = 1000

      # Test 7-bit signed delta
      # Max positive 7-bit signed
      delta_7bit = 63
      bits_7bit = <<first_timestamp::64, 1::1, 0::1, delta_7bit::7-signed>>
      metadata = %{count: 2}
      assert {:ok, [^first_timestamp, expected]} = DeltaDecoding.decode(bits_7bit, metadata)
      assert expected == first_timestamp + delta_7bit

      # Test 9-bit signed delta
      # Requires 9-bit encoding
      delta_9bit = 255
      bits_9bit = <<first_timestamp::64, 1::1, 1::1, 0::1, delta_9bit::9-signed>>
      assert {:ok, [^first_timestamp, expected]} = DeltaDecoding.decode(bits_9bit, metadata)
      assert expected == first_timestamp + delta_9bit

      # Test 12-bit signed delta
      # Requires 12-bit encoding
      delta_12bit = 2047
      bits_12bit = <<first_timestamp::64, 1::1, 1::1, 1::1, 0::1, delta_12bit::12-signed>>
      assert {:ok, [^first_timestamp, expected]} = DeltaDecoding.decode(bits_12bit, metadata)
      assert expected == first_timestamp + delta_12bit

      # Test 32-bit signed delta
      # Requires 32-bit encoding
      delta_32bit = 100_000
      bits_32bit = <<first_timestamp::64, 1::1, 1::1, 1::1, 1::1, delta_32bit::32-signed>>
      assert {:ok, [^first_timestamp, expected]} = DeltaDecoding.decode(bits_32bit, metadata)
      assert expected == first_timestamp + delta_32bit
    end

    test "decode/2 handles all delta-of-delta encoding formats" do
      first_timestamp = 1000
      first_delta = 10

      # Test with multiple delta-of-deltas requiring different encodings
      timestamps = [
        first_timestamp,
        first_timestamp + first_delta,
        # 7-bit dod
        first_timestamp + first_delta + first_delta + 63,
        # 9-bit dod
        first_timestamp + first_delta + first_delta + 63 + first_delta + 255
      ]

      {encoded_bits, metadata} =
        GorillaStream.Compression.Encoder.DeltaEncoding.encode(timestamps)

      assert {:ok, decoded} = DeltaDecoding.decode(encoded_bits, metadata)
      assert decoded == timestamps
    end

    test "decode/2 handles reconstruction with empty delta-of-deltas list" do
      # This tests the edge case where we have exactly 2 timestamps
      first_timestamp = 1000
      second_timestamp = 1100
      timestamps = [first_timestamp, second_timestamp]

      {encoded_bits, metadata} =
        GorillaStream.Compression.Encoder.DeltaEncoding.encode(timestamps)

      assert {:ok, decoded} = DeltaDecoding.decode(encoded_bits, metadata)
      assert decoded == timestamps
    end

    test "validate_bitstream/2 with non-integer expected_count" do
      # Test with invalid expected_count parameter type
      valid_bits = <<1000::64, 0::1>>

      assert {:error, "Invalid input - expected bitstring"} =
               DeltaDecoding.validate_bitstream(valid_bits, "not_integer")
    end

    test "get_bitstream_info/2 with non-map metadata" do
      # Test with invalid metadata parameter type
      valid_bits = <<1000::64, 0::1>>

      assert {:error, "Invalid input"} =
               DeltaDecoding.get_bitstream_info(valid_bits, "not_map")
    end

    test "validate_bitstream/2 handles count mismatch" do
      # Create valid data for 2 timestamps but expect 3
      timestamps = [1000, 1010]

      {encoded_bits, _metadata} =
        GorillaStream.Compression.Encoder.DeltaEncoding.encode(timestamps)

      result = DeltaDecoding.validate_bitstream(encoded_bits, 3)
      # Should either get count mismatch or validation failure due to insufficient data
      assert {:error, reason} = result
      assert reason =~ "Decoded count mismatch" or reason =~ "Validation failed"
    end
  end
end
