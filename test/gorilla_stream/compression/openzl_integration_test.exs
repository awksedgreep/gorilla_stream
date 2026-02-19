defmodule GorillaStream.Compression.OpenzlIntegrationTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Container
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

  describe "availability" do
    test "openzl_available?/0 returns a boolean" do
      result = Container.openzl_available?()
      assert is_boolean(result)
    end
  end

  describe "Gorilla.compress/2 with compression: :openzl" do
    @tag :openzl
    test "simple stream round-trip" do
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, compression: :openzl)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == @simple_stream
    end

    @tag :openzl
    test "large stream round-trip" do
      assert {:ok, compressed} = Gorilla.compress(@large_stream, compression: :openzl)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == @large_stream
    end

    @tag :openzl
    test "counter stream round-trip" do
      assert {:ok, compressed} = Gorilla.compress(@counter_stream, compression: :openzl)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == @counter_stream
    end

    @tag :openzl
    test "empty stream round-trip" do
      assert {:ok, compressed} = Gorilla.compress([], compression: :openzl)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == []
    end

    @tag :openzl
    test "compress with compression_level option" do
      opts = [compression: :openzl, compression_level: 5]
      assert {:ok, compressed} = Gorilla.compress(@simple_stream, opts)
      assert is_binary(compressed)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == @simple_stream
    end

    @tag :openzl
    test "stream with negative values round-trip" do
      negative_stream =
        for i <- 0..99 do
          {1_609_459_200 + i, -50.0 + :math.sin(i / 5) * 25}
        end

      assert {:ok, compressed} = Gorilla.compress(negative_stream, compression: :openzl)
      assert {:ok, decompressed} = Gorilla.decompress(compressed, compression: :openzl)
      assert decompressed == negative_stream
    end
  end

  describe "Container-level compress/decompress" do
    @tag :openzl
    test "basic binary round-trip" do
      data = :crypto.strong_rand_bytes(1024)
      assert {:ok, compressed} = Container.compress(data, compression: :openzl)
      assert is_binary(compressed)
      assert {:ok, ^data} = Container.decompress(compressed, compression: :openzl)
    end

    @tag :openzl
    test "empty binary round-trip" do
      assert {:ok, <<>>} = Container.compress(<<>>, compression: :openzl)
      assert {:ok, <<>>} = Container.decompress(<<>>, compression: :openzl)
    end

    @tag :openzl
    test "compress with level" do
      data = :crypto.strong_rand_bytes(1024)

      assert {:ok, compressed} =
               Container.compress(data, compression: :openzl, compression_level: 10)

      assert is_binary(compressed)
      assert {:ok, ^data} = Container.decompress(compressed, compression: :openzl)
    end
  end

  describe "streaming not supported" do
    test "create_stream_context returns error for openzl" do
      assert {:error, message} = Container.create_stream_context(:openzl, :compress)
      assert message =~ "does not support streaming"

      assert {:error, message} = Container.create_stream_context(:openzl, :decompress)
      assert message =~ "does not support streaming"
    end
  end

  describe "error handling" do
    @tag :openzl
    test "decompressing invalid data fails gracefully" do
      invalid_data = :crypto.strong_rand_bytes(64)
      result = Container.decompress(invalid_data, compression: :openzl)
      assert {:error, _reason} = result
    end

    @tag :openzl
    test "decompressing zlib data with openzl fails gracefully" do
      {:ok, zlib_compressed} = Gorilla.compress(@simple_stream, compression: :zlib)
      result = Gorilla.decompress(zlib_compressed, compression: :openzl)
      assert {:error, _reason} = result
    end
  end
end
