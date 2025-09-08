defmodule GorillaStream.Compression.MetadataV2Test do
  use ExUnit.Case, async: true
  import Bitwise

  alias GorillaStream.Compression.Gorilla
  alias GorillaStream.Compression.Decoder.Metadata, as: DecMeta

  test "emits v1-style header (80 bytes) when VM disabled" do
    stream = Enum.map(1..5, fn i -> {1_700_000_000 + i, i * 1.0} end)
    {:ok, bin} = Gorilla.compress(stream, zlib: false, victoria_metrics: false)

    {meta, remaining} = DecMeta.extract_metadata(bin)
    assert is_map(meta)
    assert is_binary(remaining)

    assert meta.header_length == 80
    assert meta.version <= 2
    assert meta.scale_decimals == 0
    assert meta.flags == 0
  end

  test "emits v2 header (84 bytes) with flags and scale_decimals when VM enabled" do
    stream = Enum.map(1..5, fn i -> {1_700_000_000 + i, 100.01 + i} end)
    {:ok, bin} = Gorilla.compress(stream, victoria_metrics: true, is_counter: true, scale_decimals: 2, zlib: false)

    {meta, _remaining} = DecMeta.extract_metadata(bin)
    assert meta.header_length == 84

    # flags: 0x1 (vm enabled) | 0x2 (is_counter)
    assert (meta.flags &&& 0x1) != 0
    assert (meta.flags &&& 0x2) != 0

    assert meta.scale_decimals == 2
  end
end

