defmodule GorillaStream.Compression.ContainerTest do
  use ExUnit.Case, async: true
  doctest GorillaStream.Compression.Container

  alias GorillaStream.Compression.Container

  @test_data "Hello, this is some test data for compression testing! " <>
               "The quick brown fox jumps over the lazy dog. " <>
               String.duplicate("Repeated content for better compression. ", 50)

  @small_data "tiny"

  describe "zstd_available?/0" do
    test "returns a boolean" do
      result = Container.zstd_available?()
      assert is_boolean(result)
    end

    test "returns true when ezstd is installed" do
      # Since we have ezstd as a dependency, it should be available
      assert Container.zstd_available?() == true
    end
  end

  describe "compress/2 with :none" do
    test "returns data unchanged" do
      assert {:ok, result} = Container.compress(@test_data, compression: :none)
      assert result == @test_data
    end

    test "default compression is :none" do
      assert {:ok, result} = Container.compress(@test_data, [])
      assert result == @test_data
    end
  end

  describe "compress/2 with :zlib" do
    test "compresses data" do
      assert {:ok, compressed} = Container.compress(@test_data, compression: :zlib)
      assert is_binary(compressed)
      assert compressed != @test_data
    end

    test "compressed data is smaller for repetitive content" do
      assert {:ok, compressed} = Container.compress(@test_data, compression: :zlib)
      assert byte_size(compressed) < byte_size(@test_data)
    end

    test "works with legacy zlib: true option" do
      assert {:ok, compressed} = Container.compress(@test_data, zlib: true)
      assert is_binary(compressed)
      assert compressed != @test_data
    end
  end

  describe "compress/2 with :zstd" do
    test "compresses data" do
      assert {:ok, compressed} = Container.compress(@test_data, compression: :zstd)
      assert is_binary(compressed)
      assert compressed != @test_data
    end

    test "compressed data is smaller for repetitive content" do
      assert {:ok, compressed} = Container.compress(@test_data, compression: :zstd)
      assert byte_size(compressed) < byte_size(@test_data)
    end
  end

  describe "compress/2 with :auto" do
    test "compresses data" do
      assert {:ok, compressed} = Container.compress(@test_data, compression: :auto)
      assert is_binary(compressed)
      assert compressed != @test_data
    end

    test "uses zstd when available" do
      # Since ezstd is installed, :auto should use zstd
      assert {:ok, auto_compressed} = Container.compress(@test_data, compression: :auto)
      assert {:ok, zstd_compressed} = Container.compress(@test_data, compression: :zstd)
      # They should produce the same output
      assert auto_compressed == zstd_compressed
    end
  end

  describe "decompress/2 with :none" do
    test "returns data unchanged" do
      assert {:ok, result} = Container.decompress(@test_data, compression: :none)
      assert result == @test_data
    end
  end

  describe "decompress/2 with :zlib" do
    test "decompresses zlib data correctly" do
      {:ok, compressed} = Container.compress(@test_data, compression: :zlib)
      assert {:ok, decompressed} = Container.decompress(compressed, compression: :zlib)
      assert decompressed == @test_data
    end

    test "works with legacy zlib: true option" do
      {:ok, compressed} = Container.compress(@test_data, zlib: true)
      assert {:ok, decompressed} = Container.decompress(compressed, zlib: true)
      assert decompressed == @test_data
    end

    test "returns error for invalid zlib data" do
      assert {:error, reason} = Container.decompress("not zlib data", compression: :zlib)
      assert reason =~ "Zlib decompression failed"
    end
  end

  describe "decompress/2 with :zstd" do
    test "decompresses zstd data correctly" do
      {:ok, compressed} = Container.compress(@test_data, compression: :zstd)
      assert {:ok, decompressed} = Container.decompress(compressed, compression: :zstd)
      assert decompressed == @test_data
    end

    test "returns error for invalid zstd data" do
      result = Container.decompress("not zstd data", compression: :zstd)
      assert {:error, reason} = result
      assert reason =~ "Zstd decompression failed"
    end
  end

  describe "decompress/2 with :auto" do
    test "decompresses auto-compressed data correctly" do
      {:ok, compressed} = Container.compress(@test_data, compression: :auto)
      assert {:ok, decompressed} = Container.decompress(compressed, compression: :auto)
      assert decompressed == @test_data
    end
  end

  describe "round-trip compression" do
    test "zlib round-trip preserves data" do
      {:ok, compressed} = Container.compress(@test_data, compression: :zlib)
      {:ok, decompressed} = Container.decompress(compressed, compression: :zlib)
      assert decompressed == @test_data
    end

    test "zstd round-trip preserves data" do
      {:ok, compressed} = Container.compress(@test_data, compression: :zstd)
      {:ok, decompressed} = Container.decompress(compressed, compression: :zstd)
      assert decompressed == @test_data
    end

    test "auto round-trip preserves data" do
      {:ok, compressed} = Container.compress(@test_data, compression: :auto)
      {:ok, decompressed} = Container.decompress(compressed, compression: :auto)
      assert decompressed == @test_data
    end

    test "round-trip works with small data" do
      for compression <- [:none, :zlib, :zstd, :auto] do
        {:ok, compressed} = Container.compress(@small_data, compression: compression)
        {:ok, decompressed} = Container.decompress(compressed, compression: compression)
        assert decompressed == @small_data, "Failed for compression: #{compression}"
      end
    end

    test "round-trip works with binary data" do
      binary_data = :crypto.strong_rand_bytes(1000)

      for compression <- [:none, :zlib, :zstd, :auto] do
        {:ok, compressed} = Container.compress(binary_data, compression: compression)
        {:ok, decompressed} = Container.decompress(compressed, compression: compression)
        assert decompressed == binary_data, "Failed for compression: #{compression}"
      end
    end

    test "round-trip works with empty binary" do
      for compression <- [:none, :zlib, :zstd, :auto] do
        {:ok, compressed} = Container.compress(<<>>, compression: compression)
        {:ok, decompressed} = Container.decompress(compressed, compression: compression)
        assert decompressed == <<>>, "Failed for compression: #{compression}"
      end
    end
  end

  describe "effective_compression/1" do
    test "returns :none for compression: :none" do
      assert Container.effective_compression(compression: :none) == :none
    end

    test "returns :zlib for compression: :zlib" do
      assert Container.effective_compression(compression: :zlib) == :zlib
    end

    test "returns :zstd for compression: :zstd" do
      assert Container.effective_compression(compression: :zstd) == :zstd
    end

    test "returns :zstd for compression: :auto when ezstd available" do
      # Since ezstd is installed
      assert Container.effective_compression(compression: :auto) == :zstd
    end

    test "returns :zlib for zlib: true legacy option" do
      assert Container.effective_compression(zlib: true) == :zlib
    end

    test "returns :none for empty options" do
      assert Container.effective_compression([]) == :none
    end
  end

  describe "compression comparison" do
    test "zstd achieves similar or better compression than zlib" do
      {:ok, zlib_compressed} = Container.compress(@test_data, compression: :zlib)
      {:ok, zstd_compressed} = Container.compress(@test_data, compression: :zstd)

      zlib_ratio = byte_size(zlib_compressed) / byte_size(@test_data)
      zstd_ratio = byte_size(zstd_compressed) / byte_size(@test_data)

      # zstd should be competitive with zlib (within 50% of zlib's ratio)
      assert zstd_ratio <= zlib_ratio * 1.5,
             "zstd ratio #{zstd_ratio} vs zlib ratio #{zlib_ratio}"
    end
  end
end
