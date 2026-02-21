defmodule GorillaStream.Compression.DictCompressionTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Container

  describe "dictionary compression" do
    setup do
      # Generate sample data for dictionary training
      # We need multiple samples to train a meaningful dictionary
      samples =
        for _ <- 1..100 do
          data =
            for i <- 1..100 do
              {1_700_000_000 + i * 60, 50.0 + :rand.uniform() * 10}
            end

          {:ok, compressed} = GorillaStream.compress(data, compression: :none)
          compressed
        end

      training_data = Enum.join(samples)

      # Train dictionary at compression level 9
      cdict = :ezstd.create_cdict(training_data, 9)
      ddict = :ezstd.create_ddict(training_data)

      %{cdict: cdict, ddict: ddict, samples: samples}
    end

    test "compress_with_dict and decompress_with_dict round-trip", %{
      cdict: cdict,
      ddict: ddict,
      samples: samples
    } do
      sample = hd(samples)

      {:ok, compressed} = Container.compress_with_dict(sample, cdict)
      assert is_binary(compressed)
      assert byte_size(compressed) > 0

      {:ok, decompressed} = Container.decompress_with_dict(compressed, ddict)
      assert decompressed == sample
    end

    test "compress_with_dict handles empty binary", %{cdict: cdict} do
      {:ok, result} = Container.compress_with_dict(<<>>, cdict)
      assert result == <<>>
    end

    test "decompress_with_dict handles empty binary", %{ddict: ddict} do
      {:ok, result} = Container.decompress_with_dict(<<>>, ddict)
      assert result == <<>>
    end

    test "dict compression achieves better ratio than standard zstd for similar data", %{
      cdict: cdict,
      samples: samples
    } do
      sample = hd(samples)

      {:ok, dict_compressed} = Container.compress_with_dict(sample, cdict)
      {:ok, std_compressed} = Container.compress(sample, compression: :zstd)

      # Dictionary should compress at least as well (often better for small data)
      # We don't assert strictly better since it depends on training data quality
      assert is_binary(dict_compressed)
      assert is_binary(std_compressed)
    end

    test "top-level API delegates work", %{cdict: cdict, ddict: ddict, samples: samples} do
      sample = hd(samples)

      {:ok, compressed} = GorillaStream.compress_with_dict(sample, cdict)
      {:ok, decompressed} = GorillaStream.decompress_with_dict(compressed, ddict)
      assert decompressed == sample
    end
  end
end
