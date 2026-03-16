defmodule GorillaStream.ChimpTest do
  use ExUnit.Case, async: true

  describe "Chimp compression" do
    test "roundtrip with basic data" do
      data = for i <- 0..99 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 10) * 15, 2)}
      end

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert length(decompressed) == 100
      assert decompressed == data
    end

    test "roundtrip with constant values" do
      data = for i <- 0..49, do: {1_700_000_000 + i * 60, 42.0}

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with counter data" do
      data = for i <- 0..99, do: {1_700_000_000 + i * 15, i * 1.0}

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with random floats" do
      :rand.seed(:exsss, {42, 42, 42})
      data = for i <- 0..999, do: {1_700_000_000 + i * 15, :rand.uniform() * 1000.0}

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with single point" do
      data = [{1_700_000_000, 42.5}]

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with two points" do
      data = [{1_700_000_000, 42.5}, {1_700_000_015, 43.1}]

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with extreme values" do
      data = [
        {1_700_000_000, 1.7976931348623157e+308},
        {1_700_000_015, -1.7976931348623157e+308},
        {1_700_000_030, 5.0e-324},
        {1_700_000_045, 0.0},
        {1_700_000_060, -0.0}
      ]

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert length(decompressed) == 5
      for {{_, expected}, {_, actual}} <- Enum.zip(data, decompressed) do
        assert expected == actual
      end
    end

    test "chimp compresses better than gorilla on gauge data" do
      data = for i <- 0..999 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 50) * 15, 2)}
      end

      {:ok, gorilla} = GorillaStream.compress(data)
      {:ok, chimp} = GorillaStream.compress(data, algorithm: :chimp)

      gorilla_bpp = byte_size(gorilla) / 1000
      chimp_bpp = byte_size(chimp) / 1000

      # Chimp should be same or better than Gorilla
      assert chimp_bpp <= gorilla_bpp * 1.1,
        "Chimp (#{Float.round(chimp_bpp, 2)} B/pt) should not be much worse than Gorilla (#{Float.round(gorilla_bpp, 2)} B/pt)"
    end

    test "chimp with zstd container" do
      data = for i <- 0..999 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 50) * 15, 2)}
      end

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp, compression: :zstd)
      {:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)

      assert decompressed == data
    end

    test "gorilla-encoded data still decompresses correctly" do
      data = for i <- 0..99 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 10) * 15, 2)}
      end

      {:ok, gorilla_compressed} = GorillaStream.compress(data)
      {:ok, decompressed} = GorillaStream.decompress(gorilla_compressed)

      assert decompressed == data
    end
  end

  describe "Chimp128 compression" do
    test "roundtrip with basic data" do
      data = for i <- 0..99 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 10) * 15, 2)}
      end

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with constant values" do
      data = for i <- 0..49, do: {1_700_000_000 + i * 60, 42.0}

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with random floats" do
      :rand.seed(:exsss, {42, 42, 42})
      data = for i <- 0..999, do: {1_700_000_000 + i * 15, :rand.uniform() * 1000.0}

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "roundtrip with single and two points" do
      for n <- [1, 2] do
        data = for i <- 0..(n - 1), do: {1_700_000_000 + i * 15, 42.0 + i}

        {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)
        {:ok, decompressed} = GorillaStream.decompress(compressed)

        assert decompressed == data, "Failed for #{n} points"
      end
    end

    test "roundtrip with repeating patterns (ring buffer benefit)" do
      # Values that repeat — ring buffer should find exact matches
      pattern = [10.0, 20.0, 30.0, 40.0, 50.0]

      data =
        for i <- 0..499 do
          {1_700_000_000 + i * 15, Enum.at(pattern, rem(i, length(pattern)))}
        end

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)
      {:ok, decompressed} = GorillaStream.decompress(compressed)

      assert decompressed == data
    end

    test "chimp128 compresses repeating patterns better than gorilla" do
      pattern = [10.0, 20.0, 30.0, 40.0, 50.0]

      data =
        for i <- 0..999 do
          {1_700_000_000 + i * 15, Enum.at(pattern, rem(i, length(pattern)))}
        end

      {:ok, gorilla} = GorillaStream.compress(data)
      {:ok, chimp128} = GorillaStream.compress(data, algorithm: :chimp128)

      gorilla_bpp = byte_size(gorilla) / 1000
      chimp128_bpp = byte_size(chimp128) / 1000

      assert chimp128_bpp < gorilla_bpp,
        "Chimp128 (#{Float.round(chimp128_bpp, 2)} B/pt) should beat Gorilla (#{Float.round(gorilla_bpp, 2)} B/pt) on repeating patterns"
    end

    test "chimp128 with zstd container" do
      data = for i <- 0..999 do
        {1_700_000_000 + i * 15, Float.round(45.0 + :math.sin(i / 50) * 15, 2)}
      end

      {:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128, compression: :zstd)
      {:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)

      assert decompressed == data
    end

    test "all three algorithms decompress correctly" do
      data = for i <- 0..99, do: {1_700_000_000 + i * 15, i * 1.5}

      for algo <- [nil, :chimp, :chimp128] do
        opts = if algo, do: [algorithm: algo], else: []
        {:ok, compressed} = GorillaStream.compress(data, opts)
        {:ok, decompressed} = GorillaStream.decompress(compressed)
        assert decompressed == data, "Failed for algorithm: #{inspect(algo)}"
      end
    end
  end
end
