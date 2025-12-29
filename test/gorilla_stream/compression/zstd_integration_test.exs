defmodule GorillaStream.Compression.ZstdIntegrationTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Gorilla

  # Test data for compression - various patterns
  @simple_stream [
    {1_609_459_200, 1.23},
    {1_609_459_201, 1.24},
    {1_609_459_202, 1.25},
    {1_609_459_203, 1.26},
    {1_609_459_204, 1.27}
  ]

  # Larger dataset for meaningful compression comparisons
  @large_stream (for i <- 0..999 do
                   {1_609_459_200 + i, 100.0 + :math.sin(i / 10) * 5}
                 end)

  # Counter data (monotonically increasing)
  @counter_stream (for i <- 0..999 do
                     {1_609_459_200 + i, 1000 + i * 10}
                   end)

  describe "Gorilla.compress/2 with compression option" do
    test "compression: :none works" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :none)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :none)
      assert decompressed == @simple_stream
    end

    test "compression: :zlib works" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :zlib)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zlib)
      assert decompressed == @simple_stream
    end

    test "compression: :zstd works" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :zstd)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @simple_stream
    end

    test "compression: :auto works" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :auto)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :auto)
      assert decompressed == @simple_stream
    end

    test "legacy zlib: true still works" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, zlib: true)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, zlib: true)
      assert decompressed == @simple_stream
    end
  end

  describe "Gorilla.compress/2 with combined options" do
    test "compression: :zstd with victoria_metrics: true" do
      opts = [compression: :zstd, victoria_metrics: true]
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, opts)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @simple_stream
    end

    test "compression: :zstd with victoria_metrics: false" do
      opts = [compression: :zstd, victoria_metrics: false]
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, opts)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @simple_stream
    end

    test "compression: :zstd with is_counter: true" do
      opts = [compression: :zstd, victoria_metrics: true, is_counter: true]
      assert {:ok, compressed} = Gorilla.compress(@counter_stream, opts)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @counter_stream
    end
  end

  describe "compression size comparison on large datasets" do
    test "zstd produces smaller output than no compression" do
      {:ok, no_compression} = Gorilla.compress(@large_stream, compression: :none)
      {:ok, zstd_compressed} = Gorilla.compress(@large_stream, compression: :zstd)

      assert byte_size(zstd_compressed) < byte_size(no_compression),
             "zstd: #{byte_size(zstd_compressed)} vs none: #{byte_size(no_compression)}"
    end

    test "zstd produces comparable size to zlib" do
      {:ok, zlib_compressed} = Gorilla.compress(@large_stream, compression: :zlib)
      {:ok, zstd_compressed} = Gorilla.compress(@large_stream, compression: :zstd)

      zlib_size = byte_size(zlib_compressed)
      zstd_size = byte_size(zstd_compressed)

      # zstd should be within 50% of zlib size (could be better or slightly worse)
      ratio = zstd_size / zlib_size

      assert ratio >= 0.5 and ratio <= 1.5,
             "zstd: #{zstd_size} vs zlib: #{zlib_size} (ratio: #{ratio})"
    end
  end

  describe "round-trip data integrity" do
    test "simple stream round-trip with zstd" do
      {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @simple_stream
    end

    test "large stream round-trip with zstd" do
      {:ok, compressed} = Gorilla.compress(@large_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @large_stream
    end

    test "counter stream round-trip with zstd" do
      {:ok, compressed} = Gorilla.compress(@counter_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == @counter_stream
    end

    test "empty stream round-trip with zstd" do
      {:ok, compressed} = Gorilla.compress([], compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == []
    end

    test "stream with negative values round-trip with zstd" do
      negative_stream =
        for i <- 0..99 do
          {1_609_459_200 + i, -50.0 + :math.sin(i / 5) * 25}
        end

      {:ok, compressed} = Gorilla.compress(negative_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == negative_stream
    end

    test "stream with large values round-trip with zstd" do
      large_value_stream =
        for i <- 0..99 do
          {1_609_459_200 + i, 1_000_000.0 + i * 0.001}
        end

      {:ok, compressed} = Gorilla.compress(large_value_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)
      assert decompressed == large_value_stream
    end

    test "stream with integer values round-trip with zstd" do
      integer_stream =
        for i <- 0..99 do
          {1_609_459_200 + i, 100 + i}
        end

      {:ok, compressed} = Gorilla.compress(integer_stream, compression: :zstd)
      {:ok, decompressed} = Gorilla.decompress(compressed, compression: :zstd)

      # Note: integers may be converted to floats during compression
      assert length(decompressed) == length(integer_stream)

      Enum.zip(decompressed, integer_stream)
      |> Enum.each(fn {{ts1, val1}, {ts2, val2}} ->
        assert ts1 == ts2
        assert val1 == val2 or val1 == val2 * 1.0
      end)
    end
  end

  describe "error handling" do
    test "decompressing zlib data with zstd fails gracefully" do
      {:ok, zlib_compressed} = Gorilla.compress(@simple_stream, compression: :zlib)
      result = Gorilla.decompress(zlib_compressed, compression: :zstd)
      assert {:error, reason} = result
      # Error could come from container or decoder level
      assert reason =~ "Zstd decompression failed" or reason =~ "Decompression failed"
    end

    test "decompressing zstd data with zlib fails gracefully" do
      {:ok, zstd_compressed} = Gorilla.compress(@simple_stream, compression: :zstd)
      result = Gorilla.decompress(zstd_compressed, compression: :zlib)
      assert {:error, reason} = result
      # Error could come from container or decoder level
      assert reason =~ "Zlib decompression failed" or reason =~ "Decompression failed"
    end
  end
end
