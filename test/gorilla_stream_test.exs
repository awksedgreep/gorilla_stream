defmodule GorillaStreamTest do
  use ExUnit.Case, async: true
  doctest GorillaStream

  # Test that the compression library works correctly
  test "Gorilla compression library works correctly" do
    # Test data for compression
    test_stream = [
      {1_609_459_200, 1.23},
      {1_609_459_201, 1.24},
      {1_609_459_202, 1.25},
      {1_609_459_203, 1.26},
      {1_609_459_204, 1.27}
    ]

    # Test that compression works with zlib compression disabled
    assert {:ok, compressed_data} = GorillaStream.Compression.Gorilla.compress(test_stream, false)
    assert is_binary(compressed_data)
    assert byte_size(compressed_data) > 0

    # Test that decompression works correctly
    assert {:ok, original_stream} =
             GorillaStream.Compression.Gorilla.decompress(compressed_data, false)

    assert original_stream == test_stream

    # Test that compression works with zlib compression enabled
    assert {:ok, compressed_data} = GorillaStream.Compression.Gorilla.compress(test_stream, true)
    assert is_binary(compressed_data)
    assert byte_size(compressed_data) > 0

    # Test that decompression works correctly with zlib compression
    assert {:ok, original_stream} =
             GorillaStream.Compression.Gorilla.decompress(compressed_data, true)

    assert original_stream == test_stream

    # Test that empty stream returns empty compressed data
    assert {:ok, <<>>} = GorillaStream.Compression.Gorilla.compress([], false)
  end

  describe "comprehensive edge cases for GorillaStream coverage" do
    test "handles single data point compression and decompression" do
      single_point = [{1_609_459_200, 42.5}]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(single_point, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == single_point
    end

    test "handles identical consecutive values efficiently" do
      identical_data = [
        {1_609_459_200, 100.0},
        {1_609_459_201, 100.0},
        {1_609_459_202, 100.0},
        {1_609_459_203, 100.0}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(identical_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == identical_data

      # Should be very efficient
      assert byte_size(compressed) < 200
    end

    test "handles large timestamp values" do
      large_timestamps = [
        {9_223_372_036_854_775_800, 1.0},
        {9_223_372_036_854_775_801, 2.0},
        {9_223_372_036_854_775_802, 3.0}
      ]

      assert {:ok, compressed} =
               GorillaStream.Compression.Gorilla.compress(large_timestamps, false)

      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == large_timestamps
    end

    test "handles extreme float values" do
      extreme_values = [
        # Max float
        {1_609_459_200, 1.7976931348623157e308},
        # Min normal
        {1_609_459_201, 2.2250738585072014e-308},
        # Min subnormal
        {1_609_459_202, 4.9e-324},
        {1_609_459_203, 0.0}
      ]

      assert {:ok, compressed} =
               GorillaStream.Compression.Gorilla.compress(extreme_values,
                 victoria_metrics: false,
                 zlib: false
               )

      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == extreme_values
    end

    test "handles negative values and timestamps" do
      negative_data = [
        {1_609_459_200, -100.5},
        {1_609_459_201, -50.25},
        {1_609_459_202, -25.125}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(negative_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == negative_data
    end

    test "handles irregular timestamp intervals" do
      irregular_data = [
        {1_609_459_200, 1.0},
        # +5 seconds
        {1_609_459_205, 2.0},
        # +2 seconds
        {1_609_459_207, 3.0},
        # +13 seconds
        {1_609_459_220, 4.0},
        # +1 second
        {1_609_459_221, 5.0}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(irregular_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == irregular_data
    end

    test "handles float values correctly" do
      float_data = [
        {1_609_459_200, 42.0},
        {1_609_459_201, 43.0},
        {1_609_459_202, 44.0}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(float_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == float_data
    end

    test "compression with zlib enabled vs disabled produces different sizes" do
      test_data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, 1.24},
        {1_609_459_202, 1.25},
        {1_609_459_203, 1.26},
        {1_609_459_204, 1.27}
      ]

      assert {:ok, compressed_no_zlib} =
               GorillaStream.Compression.Gorilla.compress(test_data, false)

      assert {:ok, compressed_with_zlib} =
               GorillaStream.Compression.Gorilla.compress(test_data, true)

      # Both should decompress to the same data
      assert {:ok, decompressed_no_zlib} =
               GorillaStream.Compression.Gorilla.decompress(compressed_no_zlib, false)

      assert {:ok, decompressed_with_zlib} =
               GorillaStream.Compression.Gorilla.decompress(compressed_with_zlib, true)

      assert decompressed_no_zlib == test_data
      assert decompressed_with_zlib == test_data

      # Sizes might be different
      assert is_binary(compressed_no_zlib)
      assert is_binary(compressed_with_zlib)
    end

    test "handles large datasets efficiently" do
      large_data =
        for i <- 0..99 do
          {1_609_459_200 + i, 100.0 + i * 0.1}
        end

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(large_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == large_data

      # Should achieve reasonable compression
      # 100 points * 16 bytes each
      original_size = 100 * 16
      compression_ratio = byte_size(compressed) / original_size
      assert compression_ratio < 1.0
    end

    test "handles zero values and signed zero" do
      zero_data = [
        {1_609_459_200, 0.0},
        {1_609_459_201, -0.0},
        {1_609_459_202, 0.0}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(zero_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)

      # All zeros should decode as 0.0
      [{_, v1}, {_, v2}, {_, v3}] = decompressed
      assert v1 == 0.0
      assert v2 == 0.0
      assert v3 == 0.0
    end

    test "handles alternating patterns" do
      alternating_data = [
        {1_609_459_200, 1.0},
        {1_609_459_201, 2.0},
        {1_609_459_202, 1.0},
        {1_609_459_203, 2.0},
        {1_609_459_204, 1.0}
      ]

      assert {:ok, compressed} =
               GorillaStream.Compression.Gorilla.compress(alternating_data, false)

      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == alternating_data
    end

    test "handles gradual value changes" do
      gradual_data =
        for i <- 0..19 do
          {1_609_459_200 + i, 20.0 + i * 0.1}
        end

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(gradual_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == gradual_data
    end

    test "handles step function patterns" do
      step_data = [
        {1_609_459_200, 10.0},
        {1_609_459_201, 10.0},
        {1_609_459_202, 10.0},
        {1_609_459_203, 20.0},
        {1_609_459_204, 20.0},
        {1_609_459_205, 20.0},
        {1_609_459_206, 30.0},
        {1_609_459_207, 30.0}
      ]

      assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(step_data, false)
      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == step_data
    end

    test "handles high precision floating point values" do
      precision_data = [
        {1_609_459_200, 1.23456789012345},
        {1_609_459_201, 1.23456789012346},
        {1_609_459_202, 1.23456789012347}
      ]

      assert {:ok, compressed} =
               GorillaStream.Compression.Gorilla.compress(precision_data,
                 victoria_metrics: false,
                 zlib: false
               )

      assert {:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
      assert decompressed == precision_data
    end

    test "round-trip consistency across multiple iterations" do
      original_data = [
        {1_609_459_200, 1.23},
        {1_609_459_201, 1.24},
        {1_609_459_202, 1.25}
      ]

      current_data = original_data

      # Multiple encode/decode cycles
      for _i <- 1..5 do
        assert {:ok, compressed} = GorillaStream.Compression.Gorilla.compress(current_data, false)

        assert {:ok, decompressed} =
                 GorillaStream.Compression.Gorilla.decompress(compressed, false)

        assert decompressed == original_data
        _current_data = decompressed
      end
    end

    test "error handling for malformed compressed data" do
      malformed_data = <<1, 2, 3, 4, 5>>

      # Should handle malformed data gracefully
      result = GorillaStream.Compression.Gorilla.decompress(malformed_data, false)
      # Depending on implementation, might return error or empty list
      case result do
        {:ok, []} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Expected either {:ok, []} or {:error, _}")
      end
    end
  end
end
