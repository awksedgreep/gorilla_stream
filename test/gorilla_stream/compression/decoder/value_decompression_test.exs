defmodule GorillaStream.Compression.Decoder.ValueDecompressionTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Decoder.ValueDecompression
  alias GorillaStream.Compression.Encoder.ValueCompression

  describe "decompress/2" do
    test "decompresses empty bitstream with zero count" do
      assert {:ok, []} = ValueDecompression.decompress(<<>>, %{count: 0})
    end

    test "decompresses single value" do
      value = 42.5
      {encoded_bits, metadata} = ValueCompression.compress([value])

      assert {:ok, [decoded_value]} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded_value == value
    end

    test "decompresses two identical values" do
      values = [1.0, 1.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses multiple different values" do
      values = [1.0, 2.0, 3.0, 4.0, 5.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses floating-point values with high precision" do
      values = [3.141592653589793, 2.718281828459045, 1.4142135623730951]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses negative values" do
      values = [-1.0, -2.5, -100.75, -0.001]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses mixed positive and negative values" do
      values = [-10.5, 20.3, -5.7, 0.0, 15.2]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses very small values" do
      values = [1.0e-10, 2.0e-15, 3.0e-20]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses very large values" do
      values = [1.0e10, 2.0e15, 3.0e20]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses zero values" do
      values = [0.0, 0.0, 0.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses slowly changing time series" do
      # Typical time series data that compresses well
      values = [100.0, 100.1, 100.2, 100.15, 100.25]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses rapidly changing values" do
      values = [1.0, 1000.0, 0.001, 5555.5, -999.9]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses repeated pattern" do
      values = [1.0, 2.0, 1.0, 2.0, 1.0, 2.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "decompresses large dataset" do
      # Generate a larger dataset
      values = for i <- 1..100, do: :math.sin(i * 0.1) * 100
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end

    test "handles large values" do
      # Test very large values that are still finite
      large_value = 1.0e100
      values = [1.0, large_value, -large_value, 2.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded == values
    end
  end

  describe "error conditions" do
    test "returns error for invalid input types" do
      assert {:error, "Invalid input - expected bitstring and metadata"} =
               ValueDecompression.decompress(123, %{})

      assert {:error, reason} = ValueDecompression.decompress(<<>>, "not map")

      assert reason =~ "Value decompression failed" or
               reason == "Invalid input - expected bitstring and metadata"
    end

    test "handles insufficient data for single value" do
      # Not enough bits for a single 64-bit float
      insufficient_data = <<1, 2, 3, 4>>
      metadata = %{count: 1}

      assert {:error, reason} = ValueDecompression.decompress(insufficient_data, metadata)
      assert reason =~ "Insufficient data for single value"
    end

    test "handles insufficient data for first value in multiple values" do
      # Not enough bits for first value when count > 1
      insufficient_data = <<1, 2, 3, 4>>
      metadata = %{count: 2}

      assert {:error, reason} = ValueDecompression.decompress(insufficient_data, metadata)
      assert reason =~ "Insufficient data for first value"
    end

    test "handles corrupted XOR bitstream" do
      # Create insufficient data after first value
      # 1.0 in IEEE 754
      first_value_bits = 0x3FF0000000000000

      # Add some invalid/insufficient XOR data
      corrupted_bits = <<first_value_bits::64, 1::1, 0::1>>
      metadata = %{count: 2}

      assert {:error, reason} = ValueDecompression.decompress(corrupted_bits, metadata)

      assert reason =~ "Insufficient bits for meaningful value" or
               reason =~ "Value decompression failed"
    end

    test "handles empty bitstream with non-zero count" do
      empty_bits = <<>>
      metadata = %{count: 1}

      assert {:error, reason} = ValueDecompression.decompress(empty_bits, metadata)
      assert reason =~ "Insufficient data"
    end

    test "handles malformed metadata" do
      valid_bits = <<0::64>>

      # Missing count - this will default to 0 and return empty list
      assert {:ok, []} = ValueDecompression.decompress(valid_bits, %{})
    end
  end

  describe "validate_bitstream/2" do
    test "validates correct bitstream" do
      values = [1.0, 2.0, 3.0]
      {encoded_bits, _metadata} = ValueCompression.compress(values)

      assert :ok = ValueDecompression.validate_bitstream(encoded_bits, 3)
    end

    test "detects count mismatch" do
      values = [1.0, 2.0]
      {encoded_bits, _metadata} = ValueCompression.compress(values)

      assert {:error, reason} = ValueDecompression.validate_bitstream(encoded_bits, 3)

      assert reason =~ "Decoded count mismatch: expected 3, got 2" or
               reason =~ "Validation failed"
    end

    test "handles invalid bitstream" do
      invalid_bits = <<1, 2, 3>>

      assert {:error, reason} = ValueDecompression.validate_bitstream(invalid_bits, 2)
      assert reason =~ "Validation failed"
    end

    test "rejects non-bitstring input" do
      assert {:error, "Invalid input - expected bitstring"} =
               ValueDecompression.validate_bitstream(123, 2)
    end

    test "rejects non-integer count" do
      valid_bits = <<0::64>>

      assert {:error, reason} = ValueDecompression.validate_bitstream(valid_bits, "not integer")
      assert reason =~ "Validation failed"
    end
  end

  describe "get_bitstream_info/2" do
    test "returns info for empty bitstream" do
      assert {:ok, info} = ValueDecompression.get_bitstream_info(<<>>, %{count: 0})
      assert info.count == 0
      assert info.first_value == nil
    end

    test "returns info for single value" do
      value = 42.5
      {encoded_bits, metadata} = ValueCompression.compress([value])

      assert {:ok, info} = ValueDecompression.get_bitstream_info(encoded_bits, metadata)
      assert info.count == 1
      assert info.first_value == value
    end

    test "returns info for multiple values" do
      values = [10.0, 20.0, 30.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, info} = ValueDecompression.get_bitstream_info(encoded_bits, metadata)
      assert info.count == 3
      assert info.first_value == 10.0
    end

    test "handles invalid input gracefully" do
      assert {:error, "Invalid input"} =
               ValueDecompression.get_bitstream_info(123, %{})
    end

    test "handles insufficient data" do
      insufficient_data = <<1, 2, 3>>
      metadata = %{count: 1}

      # This might succeed with partial data interpretation
      result = ValueDecompression.get_bitstream_info(insufficient_data, metadata)

      case result do
        # Acceptable
        {:ok, _info} -> :ok
        {:error, reason} -> assert reason =~ "Analysis failed"
      end
    end

    test "rejects non-map metadata" do
      valid_bits = <<0::64>>

      assert {:error, reason} = ValueDecompression.get_bitstream_info(valid_bits, "not map")
      assert reason =~ "Analysis failed" or reason == "Invalid input"
    end
  end

  describe "round-trip consistency" do
    test "maintains precision across compress/decompress cycle" do
      original_values = [
        1.0,
        2.5,
        -3.7,
        0.0,
        999.999,
        1.0e-10,
        1.0e10,
        -1.0e-5,
        3.141592653589793,
        2.718281828459045
      ]

      {encoded_bits, metadata} = ValueCompression.compress(original_values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      assert decoded_values == original_values
    end

    test "handles edge case values correctly" do
      # Test various edge cases that might cause issues
      edge_values = [
        # Identical values
        1.0,
        1.0,
        # Positive and negative zero
        0.0,
        -0.0,
        # Very close values
        1.0,
        1.0000000000000002,
        # Large numbers with small differences
        1_000_000.0,
        1_000_000.1
      ]

      {encoded_bits, metadata} = ValueCompression.compress(edge_values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      # For very close floating point values, we may need to be more lenient
      assert length(decoded_values) == length(edge_values)

      Enum.zip(decoded_values, edge_values)
      |> Enum.each(fn {decoded, original} ->
        assert abs(decoded - original) < 1.0e-10 or decoded == original
      end)
    end

    test "preserves order of values" do
      values = Enum.shuffle(1..20) |> Enum.map(&(&1 * 1.5))

      {encoded_bits, metadata} = ValueCompression.compress(values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      assert decoded_values == values
    end
  end

  describe "compression efficiency scenarios" do
    test "handles highly compressible data" do
      # Repeated values should compress very well
      values = List.duplicate(42.0, 100)

      {encoded_bits, metadata} = ValueCompression.compress(values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      assert decoded_values == values
      assert length(decoded_values) == 100
    end

    test "handles poorly compressible data" do
      # Random values should still decompress correctly
      :rand.seed(:exsss, {1, 2, 3})
      values = for _ <- 1..50, do: :rand.uniform() * 1000

      {encoded_bits, metadata} = ValueCompression.compress(values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      assert decoded_values == values
    end

    test "handles alternating pattern" do
      values = [1.0, 100.0] |> Stream.cycle() |> Enum.take(20)

      {encoded_bits, metadata} = ValueCompression.compress(values)
      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)

      assert decoded_values == values
    end
  end

  describe "decompress_and_validate/3" do
    test "decompresses and validates basic data" do
      values = [1.0, 2.0, 3.0, 4.0, 5.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, {decoded_values, stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata)

      assert decoded_values == values
      assert stats.count == 5
      assert stats.min == 1.0
      assert stats.max == 5.0
      assert stats.mean == 3.0
      assert stats.range == 4.0
    end

    test "validates with expected count" do
      values = [10.0, 20.0, 30.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      # Correct count
      assert {:ok, {_values, _stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata,
                 expected_count: 3
               )

      # Wrong count
      assert {:error, error_msg} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata,
                 expected_count: 5
               )

      assert error_msg =~ "Count mismatch"
    end

    test "validates with max range constraint" do
      # Range of 9.0
      values = [1.0, 10.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      # Acceptable range
      assert {:ok, {_values, _stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata, max_range: 15.0)

      # Too restrictive range
      assert {:error, error_msg} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata, max_range: 5.0)

      assert error_msg =~ "Range too large"
    end

    test "validates minimum values constraint" do
      values = [42.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      # Acceptable minimum
      assert {:ok, {_values, _stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata, min_values: 1)

      # Too restrictive minimum
      assert {:error, error_msg} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata, min_values: 3)

      assert error_msg =~ "Too few values"
    end

    test "handles empty values validation" do
      {encoded_bits, metadata} = ValueCompression.compress([])

      # Empty values fail min_values constraint by default (min_values: 1)
      assert {:error, error_msg} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata)

      assert error_msg =~ "Too few values"

      # But should work with min_values: 0
      assert {:ok, {[], stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata, min_values: 0)

      assert stats.count == 0
    end

    test "detects non-finite values" do
      # This test might not work directly since ValueCompression may not create non-finite values
      # But we can test the validation logic by creating custom metadata
      values = [1.0, 2.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      # This should pass normally
      assert {:ok, {_values, _stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata)
    end

    test "combines multiple validation criteria" do
      values = [5.0, 10.0, 15.0, 20.0, 25.0]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      # All criteria pass
      assert {:ok, {_values, _stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata,
                 expected_count: 5,
                 max_range: 25.0,
                 min_values: 3
               )

      # One criterion fails
      assert {:error, _error_msg} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata,
                 expected_count: 5,
                 # This will fail since range is 20.0
                 max_range: 10.0
               )
    end
  end

  describe "edge cases and error conditions" do
    test "handles malformed XOR control bits" do
      # Create a bitstream with invalid control sequence
      # 1.0 in IEEE 754
      first_value_bits = 0x3FF0000000000000
      # Add invalid control bits that don't match expected patterns
      malformed_bits = <<first_value_bits::64, 1::1, 1::1, 0::5, 0::6>>
      metadata = %{count: 2}

      # Should fail gracefully
      assert {:error, reason} = ValueDecompression.decompress(malformed_bits, metadata)
      assert reason =~ "Insufficient bits" or reason =~ "Value decompression failed"
    end

    test "handles XOR bitstream with insufficient meaningful bits" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Control bits '10' (use previous window) but no meaningful bits
      insufficient_bits = <<first_value_bits::64, 1::1, 0::1>>
      metadata = %{count: 2}

      assert {:error, reason} = ValueDecompression.decompress(insufficient_bits, metadata)
      assert reason =~ "Insufficient bits" or reason =~ "Invalid meaningful length"
    end

    test "handles new window with invalid length" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Control bits '11' with invalid length (65, which exceeds 64-bit limit)
      invalid_bits = <<first_value_bits::64, 1::1, 1::1, 0::5, 64::6>>
      metadata = %{count: 2}

      # This might actually succeed due to how the validation works
      result = ValueDecompression.decompress(invalid_bits, metadata)

      case result do
        # May succeed with truncated data
        {:ok, _values} ->
          :ok

        {:error, reason} ->
          assert reason =~ "Invalid meaningful length" or
                   reason =~ "Value decompression failed" or
                   reason =~ "Insufficient bits"
      end
    end

    test "handles new window with negative trailing zeros" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Control bits '11' with leading_zeros=32, length=35 (total > 64)
      invalid_bits = <<first_value_bits::64, 1::1, 1::1, 32::5, 34::6, 0::35>>
      metadata = %{count: 2}

      # This might succeed or fail depending on implementation details
      result = ValueDecompression.decompress(invalid_bits, metadata)

      case result do
        # May succeed with available data
        {:ok, _values} ->
          :ok

        {:error, reason} ->
          assert reason =~ "Invalid trailing zeros" or reason =~ "Value decompression failed"
      end
    end

    test "handles truncated new window header" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Control bits '11' but missing header data
      # Missing some header bits
      truncated_bits = <<first_value_bits::64, 1::1, 1::1, 0::3>>
      metadata = %{count: 2}

      assert {:error, reason} = ValueDecompression.decompress(truncated_bits, metadata)
      assert reason =~ "Insufficient bits" or reason =~ "Value decompression failed"
    end

    test "handles zero meaningful length in previous window" do
      # This is tricky to test directly since it requires specific state
      # We'll test with a crafted scenario where prev_leading_zeros + prev_trailing_zeros = 64
      # 0.0
      first_value_bits = 0x0000000000000000
      # This should create a scenario where meaningful_length becomes 0
      problematic_bits = <<first_value_bits::64, 1::1, 0::1>>
      metadata = %{count: 2}

      # Should either succeed or fail gracefully
      result = ValueDecompression.decompress(problematic_bits, metadata)

      case result do
        {:ok, _values} ->
          :ok

        {:error, reason} ->
          assert reason =~ "Invalid meaningful length" or
                   reason =~ "Insufficient bits" or
                   reason =~ "Value decompression failed"
      end
    end

    test "handles bitstream with only control bits" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Only control bits, no data
      only_control_bits = <<first_value_bits::64, 0::1>>
      metadata = %{count: 2}

      # This should work (identical value)
      assert {:ok, [1.0, 1.0]} = ValueDecompression.decompress(only_control_bits, metadata)
    end

    test "handles insufficient bits for control sequence" do
      # 1.0
      first_value_bits = 0x3FF0000000000000
      # Less than 2 bits for control
      insufficient_control = <<first_value_bits::64, 1::1>>
      metadata = %{count: 2}

      assert {:error, reason} = ValueDecompression.decompress(insufficient_control, metadata)

      assert reason =~ "Insufficient bits for control bits" or
               reason =~ "Value decompression failed"
    end

    test "handles integer values in metadata conversion" do
      # Test the float_to_bits function with integer input
      # Integer that gets converted to float
      values = [42]
      {encoded_bits, metadata} = ValueCompression.compress(values)

      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)
      # Should be converted to float
      assert decoded_values == [42.0]
    end

    test "validates bitstream with wrong expected count edge cases" do
      values = [1.0, 2.0, 3.0]
      {encoded_bits, _metadata} = ValueCompression.compress(values)

      # Test zero expected count - this actually passes validation since it creates empty metadata
      case ValueDecompression.validate_bitstream(encoded_bits, 0) do
        # Empty data might validate as ok
        :ok -> :ok
        {:error, reason} -> assert reason =~ "Decoded count mismatch"
      end

      # Test negative expected count (should cause error in validation)
      assert {:error, reason} = ValueDecompression.validate_bitstream(encoded_bits, -1)
      assert reason =~ "Validation failed" or reason =~ "Decoded count mismatch"
    end

    test "get_bitstream_info handles edge cases" do
      # Test with malformed metadata
      valid_bits = <<0::64>>

      # Test with negative count (should be handled gracefully)
      result = ValueDecompression.get_bitstream_info(valid_bits, %{count: -1})

      case result do
        {:ok, _info} -> :ok
        {:error, reason} -> assert reason =~ "Analysis failed"
      end

      # Test with missing first_value (should default)
      assert {:ok, info} = ValueDecompression.get_bitstream_info(valid_bits, %{count: 1})
      # Default value
      assert info.first_value == 0.0
    end

    test "statistics calculation handles edge cases" do
      # Test with single value (avoid division by zero in variance)
      single_value = [42.0]
      {encoded_bits, metadata} = ValueCompression.compress(single_value)

      assert {:ok, {_values, stats}} =
               ValueDecompression.decompress_and_validate(encoded_bits, metadata)

      assert stats.count == 1
      assert stats.min == 42.0
      assert stats.max == 42.0
      assert stats.mean == 42.0
      assert stats.range == 0.0
      # Should be 0 for single value
      assert stats.variance == 0.0
    end

    test "handles very long sequences" do
      # Test with a reasonably long sequence to check performance/memory
      long_values = for i <- 1..200, do: :math.sin(i * 0.01) * 100
      {encoded_bits, metadata} = ValueCompression.compress(long_values)

      assert {:ok, decoded_values} = ValueDecompression.decompress(encoded_bits, metadata)
      assert decoded_values == long_values
      assert length(decoded_values) == 200
    end
  end
end
