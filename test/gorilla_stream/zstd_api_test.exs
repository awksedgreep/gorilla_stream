defmodule GorillaStream.ZstdApiTest do
  use ExUnit.Case, async: true

  @test_stream [
    {1_609_459_200, 1.23},
    {1_609_459_201, 1.24},
    {1_609_459_202, 1.25}
  ]

  describe "GorillaStream.zstd_available?/0" do
    test "returns true when ezstd is installed" do
      assert GorillaStream.zstd_available?() == true
    end
  end

  describe "GorillaStream.compress/2 with compression option" do
    test "compression: :zstd works through top-level API" do
      assert {:ok, compressed} = GorillaStream.compress(@test_stream, compression: :zstd)
      assert is_binary(compressed)
    end

    test "compression: :auto works through top-level API" do
      assert {:ok, compressed} = GorillaStream.compress(@test_stream, compression: :auto)
      assert is_binary(compressed)
    end
  end

  describe "GorillaStream round-trip with zstd" do
    test "compress and decompress with zstd" do
      {:ok, compressed} = GorillaStream.compress(@test_stream, compression: :zstd)
      {:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)
      assert decompressed == @test_stream
    end

    test "compress and decompress with auto" do
      {:ok, compressed} = GorillaStream.compress(@test_stream, compression: :auto)
      {:ok, decompressed} = GorillaStream.decompress(compressed, compression: :auto)
      assert decompressed == @test_stream
    end
  end
end
