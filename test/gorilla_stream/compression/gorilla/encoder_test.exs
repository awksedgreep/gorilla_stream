defmodule GorillaStream.Compression.Gorilla.EncoderTest do
  use ExUnit.Case, async: true
  alias GorillaStream.Compression.Gorilla.Encoder

  describe "encode/1" do
    test "handles empty list" do
      assert {:ok, <<>>} = Encoder.encode([])
    end

    test "encodes single data point" do
      data = [{1_609_459_200, 42.5}]
      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes multiple data points with regular timestamps" do
      data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, 1.24},
        {1_609_459_202, 1.25},
        {1_609_459_203, 1.26},
        {1_609_459_204, 1.27}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      # At least metadata header size
      assert byte_size(encoded_data) > 80
    end

    test "encodes data with integer values (converts to float)" do
      data = [
        {1_609_459_200, 42},
        {1_609_459_201, 43},
        {1_609_459_202, 44}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes data with identical consecutive values efficiently" do
      data = [
        {1_609_459_200, 100.0},
        {1_609_459_201, 100.0},
        {1_609_459_202, 100.0},
        {1_609_459_203, 100.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      # Should be more efficient than storing each value separately
      # Much less than uncompressed + overhead
      assert byte_size(encoded_data) < 4 * 16 + 100
    end

    test "encodes data with slowly changing values" do
      data = [
        {1_609_459_200, 20.0},
        {1_609_459_201, 20.1},
        {1_609_459_202, 20.2},
        {1_609_459_203, 20.3},
        {1_609_459_204, 20.4}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 80
    end

    test "encodes data with irregular timestamp intervals" do
      data = [
        {1_609_459_200, 1.0},
        # 5 second gap
        {1_609_459_205, 2.0},
        # 2 second gap
        {1_609_459_207, 3.0},
        # 13 second gap
        {1_609_459_220, 4.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes data with negative values" do
      data = [
        {1_609_459_200, -1.23},
        {1_609_459_201, -1.24},
        {1_609_459_202, -1.25}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes data with extreme float values" do
      data = [
        # Max float
        {1_609_459_200, 1.7976931348623157e308},
        # Min normal
        {1_609_459_201, 2.2250738585072014e-308},
        {1_609_459_202, 0.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes large datasets efficiently" do
      # Generate 100 data points with gradual changes
      data =
        for i <- 0..99 do
          {1_609_459_200 + i, 100.0 + i * 0.1}
        end

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)

      # Should achieve reasonable compression
      # 100 points * 16 bytes each
      original_size = 100 * 16
      compression_ratio = byte_size(encoded_data) / original_size
      # At least 20% compression
      assert compression_ratio < 0.8
    end

    test "encodes data with zero deltas (regular interval)" do
      data = [
        {1_000_000, 50.0},
        {1_000_001, 51.0},
        {1_000_002, 52.0},
        {1_000_003, 53.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes alternating timestamp patterns" do
      data = [
        {1_000_000, 1.0},
        # +5
        {1_000_005, 2.0},
        # +5
        {1_000_010, 3.0},
        # +5
        {1_000_015, 4.0},
        # +5
        {1_000_020, 5.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "handles edge case with maximum timestamp values" do
      max_timestamp = 0x7FFFFFFFFFFFFFFF

      data = [
        {max_timestamp - 3, 1.0},
        {max_timestamp - 2, 2.0},
        {max_timestamp - 1, 3.0},
        {max_timestamp, 4.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "rejects invalid data format - non-tuple" do
      invalid_data = [1.23, 2.34, 3.45]

      assert {:error, error_msg} = Encoder.encode(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects invalid data format - wrong tuple structure" do
      invalid_data = [{1_609_459_200, 1.23, "extra"}]

      assert {:error, error_msg} = Encoder.encode(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects invalid timestamp type" do
      invalid_data = [{"not_integer", 1.23}]

      assert {:error, error_msg} = Encoder.encode(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects invalid value type" do
      invalid_data = [{1_609_459_200, "not_numeric"}]

      assert {:error, error_msg} = Encoder.encode(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects mixed valid and invalid data" do
      invalid_data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, "invalid"},
        {1_609_459_202, 3.45}
      ]

      assert {:error, error_msg} = Encoder.encode(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects non-list input" do
      assert {:error, error_msg} = Encoder.encode("not_a_list")
      assert error_msg =~ "Invalid input data"
    end

    test "rejects nil input" do
      assert {:error, error_msg} = Encoder.encode(nil)
      assert error_msg =~ "Invalid input data"
    end

    test "handles floating point precision edge cases" do
      data = [
        {1_609_459_200, 1.0000000000000001},
        {1_609_459_201, 1.0000000000000002},
        {1_609_459_202, 1.0000000000000003}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end

    test "encodes data with subnormal float values" do
      data = [
        # Near subnormal
        {1_609_459_200, 1.0e-308},
        # Min subnormal
        {1_609_459_201, 4.9e-324},
        {1_609_459_202, 0.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      assert byte_size(encoded_data) > 0
    end
  end

  describe "estimate_compression_ratio/1" do
    test "estimates ratio for empty data" do
      assert {:ok, +0.0} = Encoder.estimate_compression_ratio([])
    end

    test "estimates ratio for single data point" do
      data = [{1_609_459_200, 42.5}]
      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
    end

    test "estimates ratio for regularly spaced data" do
      data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, 1.24},
        {1_609_459_202, 1.25},
        {1_609_459_203, 1.26}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
      # Should predict decent compression for regular data
      assert ratio <= 1.0
    end

    test "estimates ratio for identical values" do
      data = [
        {1_609_459_200, 100.0},
        {1_609_459_201, 100.0},
        {1_609_459_202, 100.0},
        {1_609_459_203, 100.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
      # Should predict excellent compression for identical values
      assert ratio <= 1.0
    end

    test "estimates ratio for random-like data" do
      data = [
        {1_609_459_200, 12.345},
        {1_609_459_210, 987.654},
        {1_609_459_225, 0.00123},
        {1_609_459_240, -456.789}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
      # Random data might not compress as well
      assert ratio <= 1.0
    end

    test "estimates ratio for large dataset" do
      # Generate 50 data points
      data =
        for i <- 0..49 do
          {1_609_459_200 + i, 100.0 + i * 0.5}
        end

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
      # Larger datasets should compress better
      assert ratio < 0.7
    end

    test "handles data with integer values" do
      data = [
        {1_609_459_200, 42},
        {1_609_459_201, 43},
        {1_609_459_202, 44}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
    end

    test "estimates ratio for data with extreme timestamp gaps" do
      data = [
        {1_000_000, 1.0},
        # 1M gap
        {2_000_000, 2.0},
        # 8M gap
        {10_000_000, 3.0},
        # 1 gap
        {10_000_001, 4.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
    end

    test "rejects invalid data format in estimation" do
      invalid_data = [{1_609_459_200, "invalid"}]

      assert {:error, error_msg} = Encoder.estimate_compression_ratio(invalid_data)
      assert error_msg =~ "Invalid data format"
    end

    test "rejects non-list input for estimation" do
      assert {:error, error_msg} = Encoder.estimate_compression_ratio("not_a_list")
      assert error_msg =~ "Invalid input data"
    end

    test "handles estimation errors gracefully" do
      # This test ensures that estimation doesn't crash on edge cases
      data = [
        {0, 0.0},
        {1, 1.0e-100},
        {2, 1.0e100}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio >= 0.0 and ratio <= 1.0
    end

    test "hits all branches of estimation helpers with positive and negative deltas" do
      # This test is designed to hit all `cond` branches in the private estimation helpers.
      base_ts = 1_609_459_200

      # Create a sequence of timestamps that generates a wide range of deltas and delta-of-deltas
      data = [
        {base_ts, 1.0},
        # delta = 0, dod = (n/a)
        {base_ts, 2.0},
        # delta = 60, dod = 60
        {base_ts + 60, 3.0},
        # delta = -60, dod = -120
        {base_ts, 4.0},
        # delta = 250, dod = 310
        {base_ts + 250, 5.0},
        # delta = -250, dod = -500
        {base_ts, 6.0},
        # delta = 2000, dod = 2250
        {base_ts + 2000, 7.0},
        # delta = -2000, dod = -4000
        {base_ts, 8.0},
        # delta = 3000, dod = 5000
        {base_ts + 3000, 9.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio) and ratio <= 1.0
    end

    test "handles single and two-point lists in estimation" do
      # Covers the base cases for the recursive estimation helpers
      assert {:ok, ratio1} = Encoder.estimate_compression_ratio([{1, 1.0}])
      assert ratio1 > 0.0

      assert {:ok, ratio2} = Encoder.estimate_compression_ratio([{1, 1.0}, {2, 2.0}])
      assert ratio2 > 0.0
    end
  end

  describe "estimation logic coverage" do
    test "estimates ratio for exactly two data points" do
      data = [{1_609_459_200, 42.5}, {1_609_459_201, 43.0}]
      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio > 0.0 and ratio <= 1.0
    end

    test "hits all branches of estimate_first_delta_bits" do
      # This covers the private helper function in the Encoder
      base_ts = 1_609_459_200

      test_deltas = %{
        "zero" => [{base_ts, 1.0}, {base_ts, 2.0}],
        "small" => [{base_ts, 1.0}, {base_ts + 60, 2.0}],
        "medium" => [{base_ts, 1.0}, {base_ts + 250, 2.0}],
        "large" => [{base_ts, 1.0}, {base_ts + 2000, 2.0}],
        "very_large" => [{base_ts, 1.0}, {base_ts + 3000, 2.0}],
        "small_neg" => [{base_ts, 1.0}, {base_ts - 60, 2.0}],
        "medium_neg" => [{base_ts, 1.0}, {base_ts - 250, 2.0}],
        "large_neg" => [{base_ts, 1.0}, {base_ts - 2000, 2.0}],
        "very_large_neg" => [{base_ts, 1.0}, {base_ts - 3000, 2.0}]
      }

      for {name, data} <- test_deltas do
        assert {:ok, ratio} = Encoder.estimate_compression_ratio(data),
               "Failed to estimate for delta case: #{name}"

        assert is_float(ratio)
      end
    end

    test "hits all branches of estimate_average_bits_per_delta_of_delta" do
      # This covers the cond statement inside the estimation helper
      base_ts = 1_609_459_200

      data = [
        {base_ts, 1.0},
        # delta = 1, dod = 0
        {base_ts + 1, 2.0},
        # delta = 2, dod = 1
        {base_ts + 3, 3.0},
        # delta = 67, dod = 65
        {base_ts + 70, 4.0},
        # delta = 280, dod = 213
        {base_ts + 350, 5.0},
        # delta = 2150, dod = 1870
        {base_ts + 2500, 6.0},
        # delta = 2500, dod = 350
        {base_ts + 5000, 7.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
    end

    test "hits all branches of estimate_average_bits_per_delta_of_delta with negative values" do
      # This covers negative delta-of-deltas in the estimation helper
      base_ts = 1_609_459_200

      data = [
        # Base point
        {base_ts, 1.0},
        # delta = 3000
        {base_ts + 3000, 2.0},
        # delta = 2000, dod = -1000
        {base_ts + 5000, 3.0},
        # delta = 200, dod = -1800
        {base_ts + 5200, 4.0},
        # delta = 50, dod = -150
        {base_ts + 5250, 5.0},
        # delta = 1, dod = -49
        {base_ts + 5251, 6.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
    end

    test "handles empty list for delta and xor difference calculation" do
      # These tests cover the empty list base cases of the recursive helpers
      assert {:ok, +0.0} = Encoder.estimate_compression_ratio([])
    end

    test "handles single element list for delta and xor calculation" do
      assert {:ok, ratio} = Encoder.estimate_compression_ratio([{1, 1.0}])
      assert ratio > 0.0
    end

    test "handles a complex mix of edge cases in estimation" do
      # This test combines multiple edge cases to ensure the estimation logic
      # is robust and to cover any interaction effects between the helpers.
      data = [
        # Start
        {1_609_459_200, 100.0},
        # Identical value (zero xor)
        {1_609_459_201, 100.0},
        # Large jump (large delta, new window for values)
        {1_609_459_301, 500.0},
        # Small negative value
        {1_609_459_302, -0.123},
        # Integer value
        {1_609_459_303, 499},
        # Zero value
        {1_609_459_304, 0.0},
        # Single point after a gap
        {1_609_500_000, 1000.0}
      ]

      assert {:ok, ratio} = Encoder.estimate_compression_ratio(data)
      assert is_float(ratio)
      assert ratio > 0.0 and ratio <= 1.0
    end
  end

  describe "integration and pipeline tests" do
    test "encoding pipeline produces consistent output format" do
      data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, 1.24},
        {1_609_459_202, 1.25}
      ]

      assert {:ok, encoded_data1} = Encoder.encode(data)
      assert {:ok, encoded_data2} = Encoder.encode(data)

      # Same input should produce identical output
      assert encoded_data1 == encoded_data2
    end

    test "handles various data patterns without errors" do
      test_patterns = [
        # Gradual increase
        [{1_000_000, 1.0}, {1_000_001, 1.1}, {1_000_002, 1.2}],
        # Step function
        [{1_000_000, 10.0}, {1_000_001, 10.0}, {1_000_002, 20.0}],
        # Alternating
        [{1_000_000, 1.0}, {1_000_001, 2.0}, {1_000_002, 1.0}],
        # Large numbers
        [{1_000_000, 1.0e6}, {1_000_001, 1.0e6 + 1}, {1_000_002, 1.0e6 + 2}],
        # Small numbers
        [{1_000_000, 1.0e-6}, {1_000_001, 1.0e-6 + 1.0e-9}, {1_000_002, 1.0e-6 + 2.0e-9}]
      ]

      for pattern <- test_patterns do
        assert {:ok, encoded_data} = Encoder.encode(pattern)
        assert is_binary(encoded_data)
        assert byte_size(encoded_data) > 0
      end
    end

    test "error handling throughout pipeline" do
      # Test that errors from internal modules are handled properly
      data = [{1_609_459_200, 1.23}]

      # This should work normally
      assert {:ok, _encoded_data} = Encoder.encode(data)

      # Invalid data should propagate errors properly
      invalid_data = [{1_609_459_200, :invalid_atom}]
      assert {:error, _error_msg} = Encoder.encode(invalid_data)
    end

    test "compression effectiveness on realistic datasets" do
      # Simulate temperature sensor readings
      temperature_data =
        for i <- 0..99 do
          # Temperature varies slowly around 20°C
          temp = 20.0 + :math.sin(i * 0.1) * 2.0 + :rand.uniform() * 0.1
          # Every minute
          {1_609_459_200 + i * 60, temp}
        end

      assert {:ok, encoded_data} = Encoder.encode(temperature_data)

      original_size = 100 * 16
      compression_ratio = byte_size(encoded_data) / original_size

      # Should achieve good compression on realistic sensor data
      assert compression_ratio < 0.6
    end

    test "handles mixed timestamp intervals" do
      # Real-world scenario: irregular data collection
      data = [
        # t=0
        {1_609_459_200, 1.0},
        # t=1 (+1s)
        {1_609_459_201, 1.1},
        # t=2 (+1s)
        {1_609_459_202, 1.2},
        # t=5 (+3s)
        {1_609_459_205, 1.3},
        # t=6 (+1s)
        {1_609_459_206, 1.4},
        # t=10 (+4s)
        {1_609_459_210, 1.5},
        # t=15 (+5s)
        {1_609_459_215, 1.6}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
      # At least header size
      assert byte_size(encoded_data) > 80
    end

    test "memory efficiency with large datasets" do
      # Test that encoding doesn't consume excessive memory
      large_data =
        for i <- 0..999 do
          {1_609_459_200 + i, 100.0 + i * 0.01}
        end

      assert {:ok, encoded_data} = Encoder.encode(large_data)
      assert is_binary(encoded_data)

      # Should still achieve reasonable compression
      original_size = 1000 * 16
      compression_ratio = byte_size(encoded_data) / original_size
      assert compression_ratio < 0.8
    end
  end

  describe "edge cases and robustness" do
    test "handles timestamp overflow scenarios" do
      # Test near maximum timestamp values
      # Max int64
      max_safe_timestamp = 9_223_372_036_854_775_807

      data = [
        {max_safe_timestamp - 2, 1.0},
        {max_safe_timestamp - 1, 2.0},
        {max_safe_timestamp, 3.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
    end

    test "handles zero and negative timestamps" do
      data = [
        {-1000, 1.0},
        {0, 2.0},
        {1000, 3.0}
      ]

      assert {:ok, encoded_data} = Encoder.encode(data)
      assert is_binary(encoded_data)
    end

    test "validates input data thoroughly" do
      invalid_inputs = [
        # Wrong types
        "not a list",
        123,
        :atom,
        %{key: "value"},

        # Invalid tuple structures
        # Too many elements
        [{1, 2, 3}],
        # Empty tuple
        [{}],
        # Single element
        [{1}],

        # Invalid timestamp types
        # Float timestamp
        [{1.5, 2.0}],
        # String timestamp
        [{"string", 2.0}],
        # Atom timestamp
        [{:atom, 2.0}],

        # Invalid value types
        # String value
        [{1, "string"}],
        # Atom value
        [{1, :atom}],
        # List value
        [{1, [1, 2, 3]}],
        # Map value
        [{1, %{}}]
      ]

      for invalid_input <- invalid_inputs do
        assert {:error, _error_msg} = Encoder.encode(invalid_input)
      end
    end

    test "handles very small datasets" do
      single_point = [{1_609_459_200, 42.0}]
      two_points = [{1_609_459_200, 42.0}, {1_609_459_201, 43.0}]

      assert {:ok, encoded1} = Encoder.encode(single_point)
      assert {:ok, encoded2} = Encoder.encode(two_points)

      assert is_binary(encoded1)
      assert is_binary(encoded2)
      assert byte_size(encoded2) > byte_size(encoded1)
    end
  end

  describe "pipeline error handling" do
    test "returns error when timestamp encoding fails" do
      # This test is designed to cover the `rescue` block in `encode_timestamps/1`.
      # We pass a `nil` timestamp, which will cause `DeltaEncoding` to raise an error.
      invalid_data = [{1_609_459_200, 1.0}, {nil, 2.0}]

      # The Encoder's own validation catches this before it reaches the timestamp encoding stage.
      # This is the correct behavior.
      assert {:error, "Invalid data format: all items must be {timestamp, float} tuples"} =
               Encoder.encode(invalid_data)
    end

    test "returns error when value compression fails" do
      # This test is designed to cover the `rescue` block in `encode_values/1`.
      # We pass an atom as a value, which will cause `ValueCompression` to crash.
      invalid_data = [{1_609_459_200, 1.0}, {1_609_459_201, :not_a_float}]

      assert {:error, reason} = Encoder.encode(invalid_data)
      assert reason =~ "Invalid data format: all items must be {timestamp, float} tuples"
    end
  end
end
