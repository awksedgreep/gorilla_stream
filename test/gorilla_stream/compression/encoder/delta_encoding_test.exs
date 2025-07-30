defmodule GorillaStream.Compression.Encoder.DeltaEncodingTest do
  use ExUnit.Case, async: true
  alias GorillaStream.Compression.Encoder.DeltaEncoding

  describe "encode/1" do
    test "handles empty list" do
      assert {<<>>, %{count: 0}} = DeltaEncoding.encode([])
    end

    test "handles single timestamp" do
      timestamp = 1_609_459_200
      {encoded_bits, metadata} = DeltaEncoding.encode([timestamp])

      assert metadata.count == 1
      assert metadata.first_timestamp == timestamp
      assert bit_size(encoded_bits) == 64
      # Should just be the timestamp itself
      <<decoded_timestamp::64>> = encoded_bits
      assert decoded_timestamp == timestamp
    end

    test "handles two timestamps with regular delta" do
      timestamps = [1_609_459_200, 1_609_459_201]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 2
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 1
      # Should include first delta encoding
      assert bit_size(encoded_bits) > 64
    end

    test "handles regular time series with consistent intervals" do
      timestamps = [1_609_459_200, 1_609_459_201, 1_609_459_202, 1_609_459_203, 1_609_459_204]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 5
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 1
      # With consistent deltas, delta-of-deltas should be mostly zeros (1 bit each)
      # Should be quite compact
      assert bit_size(encoded_bits) < 300
    end

    test "handles irregular intervals" do
      timestamps = [1_609_459_200, 1_609_459_202, 1_609_459_205, 1_609_459_209, 1_609_459_214]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 5
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 2
      # With varying deltas, should need more bits
      assert bit_size(encoded_bits) >= 100
    end

    test "handles zero delta (repeated timestamps)" do
      timestamps = [1_609_459_200, 1_609_459_200, 1_609_459_200]
      {_encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 3
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 0
    end

    test "handles negative deltas (decreasing timestamps)" do
      timestamps = [1_609_459_200, 1_609_459_199, 1_609_459_198]
      {_encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 3
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == -1
    end

    test "handles large positive deltas" do
      timestamps = [1_609_459_200, 1_609_459_200 + 1000, 1_609_459_200 + 2000]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 3
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 1000
      # Large deltas should require more bits
      assert bit_size(encoded_bits) > 80
    end

    test "handles large negative deltas" do
      timestamps = [1_609_459_200, 1_609_459_200 - 1000, 1_609_459_200 - 2000]
      {_encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 3
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == -1000
    end

    test "handles very large deltas requiring 32-bit encoding" do
      large_delta = 1_000_000_000
      timestamps = [1_609_459_200, 1_609_459_200 + large_delta]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 2
      assert metadata.first_delta == large_delta
      # Should use the 32-bit encoding path
      assert bit_size(encoded_bits) > 64 + 32
    end

    test "handles boundary conditions for delta-of-delta encoding" do
      # Test the boundary values for different encoding lengths
      base = 1_609_459_200

      # Test delta-of-delta = 0 (should use 1 bit)
      timestamps = [base, base + 1, base + 2, base + 3]
      {bits, _} = DeltaEncoding.encode(timestamps)
      # Should be compact due to zero delta-of-deltas
      assert bit_size(bits) < 100

      # Test delta-of-delta at 7-bit boundary (-63 to 64)
      # delta-of-delta = 64
      timestamps = [base, base + 1, base + 65]
      {bits, _} = DeltaEncoding.encode(timestamps)
      assert bit_size(bits) > 64

      # Test delta-of-delta at 9-bit boundary (-255 to 256)
      # delta-of-delta = 256
      timestamps = [base, base + 1, base + 257]
      {bits, _} = DeltaEncoding.encode(timestamps)
      assert bit_size(bits) > 64
    end

    test "handles edge case with maximum timestamp values" do
      # Large but valid timestamp
      max_timestamp = 9_999_999_999
      timestamps = [max_timestamp - 2, max_timestamp - 1, max_timestamp]
      {_encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 3
      assert metadata.first_timestamp == max_timestamp - 2
      assert metadata.first_delta == 1
    end

    test "handles alternating pattern creating variable delta-of-deltas" do
      base = 1_609_459_200
      timestamps = [base, base + 1, base + 3, base + 4, base + 6, base + 7]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 6
      assert metadata.first_delta == 1
      # Alternating pattern should create non-zero delta-of-deltas
      assert bit_size(encoded_bits) > 100
    end

    test "encodes timestamps in ascending order correctly" do
      timestamps = Enum.to_list(1_609_459_200..1_609_459_210)
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 11
      assert metadata.first_timestamp == 1_609_459_200
      assert metadata.first_delta == 1
      # Regular interval should compress well
      assert bit_size(encoded_bits) < 200
    end

    test "handles rapid timestamp changes" do
      base = 1_609_459_200
      timestamps = [base, base + 1, base + 100, base + 101, base + 200]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 5
      assert metadata.first_delta == 1
      # Should handle the large jumps
      assert bit_size(encoded_bits) > 100
    end

    test "produces consistent metadata format" do
      timestamps = [1_609_459_200, 1_609_459_201, 1_609_459_202]
      {_encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert Map.has_key?(metadata, :count)
      assert Map.has_key?(metadata, :first_timestamp)
      assert Map.has_key?(metadata, :first_delta)
      assert is_integer(metadata.count)
      assert is_integer(metadata.first_timestamp)
      assert is_integer(metadata.first_delta)
    end

    test "bit size scales reasonably with input size" do
      small_timestamps = [1_609_459_200, 1_609_459_201, 1_609_459_202]
      large_timestamps = Enum.to_list(1_609_459_200..1_609_459_250)

      {small_bits, _} = DeltaEncoding.encode(small_timestamps)
      {large_bits, _} = DeltaEncoding.encode(large_timestamps)

      # Larger input should generally produce larger output, but efficiently
      assert bit_size(large_bits) > bit_size(small_bits)
      # But should be much smaller than naive encoding
      naive_size = length(large_timestamps) * 64
      assert bit_size(large_bits) < naive_size / 2
    end

    test "handles mixed positive and negative delta patterns" do
      base = 1_609_459_200
      timestamps = [base, base + 5, base + 3, base + 8, base + 1]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.count == 5
      assert metadata.first_delta == 5
      # Mixed patterns should still encode successfully
      assert bit_size(encoded_bits) > 64
    end
  end

  describe "first delta encoding edge cases" do
    test "encodes zero first delta" do
      # Same timestamp
      timestamps = [1_609_459_200, 1_609_459_200]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == 0
      # Should use minimal encoding for zero
      # timestamp + 1 bit for zero delta
      assert bit_size(encoded_bits) == 64 + 1
    end

    test "encodes small positive first delta efficiently" do
      # Delta = 1
      timestamps = [1_609_459_200, 1_609_459_201]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == 1
      # Should use 7-bit encoding (1 + 1 + 7 = 9 bits for delta)
      assert bit_size(encoded_bits) == 64 + 9
    end

    test "encodes small negative first delta efficiently" do
      # Delta = -1
      timestamps = [1_609_459_200, 1_609_459_199]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == -1
      # Should use 7-bit signed encoding
      assert bit_size(encoded_bits) == 64 + 9
    end

    test "encodes medium first delta with 9 bits" do
      # Delta = 100
      timestamps = [1_609_459_200, 1_609_459_200 + 100]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == 100
      # Should use 9-bit encoding (1 + 1 + 1 + 9 = 12 bits for delta)
      assert bit_size(encoded_bits) == 64 + 12
    end

    test "encodes large first delta with 12 bits" do
      # Delta = 1000
      timestamps = [1_609_459_200, 1_609_459_200 + 1000]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == 1000
      # Should use 12-bit encoding
      # 4 control bits + 12 data bits
      assert bit_size(encoded_bits) == 64 + 16
    end

    test "encodes very large first delta with 32 bits" do
      large_delta = 100_000
      timestamps = [1_609_459_200, 1_609_459_200 + large_delta]
      {encoded_bits, metadata} = DeltaEncoding.encode(timestamps)

      assert metadata.first_delta == large_delta
      # Should use 32-bit encoding
      # 4 control bits + 32 data bits
      assert bit_size(encoded_bits) == 64 + 36
    end
  end

  describe "delta-of-delta encoding patterns" do
    test "encodes zero delta-of-delta with single bit" do
      # Regular intervals should produce zero delta-of-deltas
      timestamps = [1_609_459_200, 1_609_459_201, 1_609_459_202, 1_609_459_203]
      {encoded_bits, _metadata} = DeltaEncoding.encode(timestamps)

      # Should be: 64 (first timestamp) + 9 (first delta=1) + 1 + 1 (two zero delta-of-deltas)
      assert bit_size(encoded_bits) == 64 + 9 + 1 + 1
    end

    test "encodes small delta-of-delta efficiently" do
      base = 1_609_459_200
      # Deltas: 1, 2 -> delta-of-delta: 1
      timestamps = [base, base + 1, base + 3]
      {encoded_bits, _metadata} = DeltaEncoding.encode(timestamps)

      # Should use 7-bit encoding for delta-of-delta = 1
      # timestamp + first_delta + delta_of_delta
      expected_size = 64 + 9 + 9
      assert bit_size(encoded_bits) == expected_size
    end

    test "handles boundary values for delta-of-delta encoding" do
      base = 1_609_459_200

      # Test exactly at 7-bit boundary (delta-of-delta = 64)
      # deltas: 1, 65 -> dod: 64
      timestamps = [base, base + 1, base + 66]
      {encoded_bits, _} = DeltaEncoding.encode(timestamps)
      # Should fit in 7-bit encoding
      assert bit_size(encoded_bits) == 64 + 9 + 9

      # Test just over 7-bit boundary (delta-of-delta = 65)
      # deltas: 1, 66 -> dod: 65
      timestamps = [base, base + 1, base + 67]
      {encoded_bits, _} = DeltaEncoding.encode(timestamps)
      # Should use 9-bit encoding
      assert bit_size(encoded_bits) == 64 + 9 + 12
    end
  end
end
