defmodule GorillaStream.Compression.NifCompatibilityTest do
  use ExUnit.Case, async: true

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
  alias GorillaStream.Compression.Gorilla.NIF

  @moduletag :nif

  describe "NIF availability" do
    test "NIF module is loaded" do
      assert Encoder.nif_available?()
      assert Decoder.nif_available?()
    end
  end

  describe "NIF encode round-trip" do
    test "basic float data" do
      data = [
        {1_000_000, 36.5},
        {1_000_060, 36.7},
        {1_000_120, 36.6},
        {1_000_180, 36.8}
      ]

      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      assert length(decoded) == length(data)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end

    test "single data point" do
      data = [{1_000_000, 42.0}]
      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)
      assert decoded == data
    end

    test "two data points" do
      data = [{1_000_000, 42.0}, {1_000_060, 43.0}]
      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end

    test "integer values" do
      data = [
        {1_000_000, 100},
        {1_000_060, 200},
        {1_000_120, 300}
      ]

      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig * 1.0, val_dec, 1.0e-10
      end
    end

    test "identical values" do
      data = for i <- 0..9, do: {1_000_000 + i * 60, 42.0}
      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end

    test "empty data" do
      {:ok, encoded} = Encoder.encode([])
      assert encoded == <<>>
      {:ok, decoded} = Decoder.decode(<<>>)
      assert decoded == []
    end

    test "larger dataset" do
      base_ts = 1_700_000_000
      data = for i <- 0..99, do: {base_ts + i * 60, 20.0 + :math.sin(i / 10.0)}
      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      assert length(decoded) == 100

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end

    test "irregular timestamps" do
      data = [
        {1_000_000, 1.0},
        {1_000_060, 2.0},
        {1_000_200, 3.0},
        {1_000_201, 4.0},
        {1_002_000, 5.0}
      ]

      {:ok, encoded} = Encoder.encode(data)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end
  end

  describe "cross-decode compatibility" do
    test "NIF-encoded data decoded by Elixir" do
      data = [
        {1_000_000, 36.5},
        {1_000_060, 36.7},
        {1_000_120, 36.6}
      ]

      {:ok, nif_encoded} = NIF.nif_gorilla_encode(data, %{})
      {:ok, decoded} = Decoder.decode_elixir(nif_encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end

    test "Elixir-encoded data decoded by NIF" do
      data = [
        {1_000_000, 36.5},
        {1_000_060, 36.7},
        {1_000_120, 36.6}
      ]

      {:ok, elixir_encoded} = Encoder.encode_elixir(data, [])
      {:ok, decoded} = NIF.nif_gorilla_decode(elixir_encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 1.0e-10
      end
    end
  end

  describe "wire format compatibility" do
    test "NIF and Elixir produce same inner payload" do
      data = [
        {1_000_000, 36.5},
        {1_000_060, 36.7},
        {1_000_120, 36.6}
      ]

      {:ok, nif_encoded} = NIF.nif_gorilla_encode(data, %{})
      {:ok, elixir_encoded} = Encoder.encode_elixir(data, [])

      # Headers may differ in creation_time and compression_ratio float precision,
      # but the packed payload after the outer header should match.
      # V1 header is 80 bytes
      nif_payload = binary_part(nif_encoded, 80, byte_size(nif_encoded) - 80)
      elixir_payload = binary_part(elixir_encoded, 80, byte_size(elixir_encoded) - 80)

      assert nif_payload == elixir_payload
    end

    test "NIF and Elixir headers have same structure" do
      data = [{1_000_000, 42.0}, {1_000_060, 43.0}]

      {:ok, nif_encoded} = NIF.nif_gorilla_encode(data, %{})
      {:ok, elixir_encoded} = Encoder.encode_elixir(data, [])

      # Parse both headers to compare fields (except creation_time)
      <<nif_magic::64, nif_ver::16, nif_hdr_size::16, nif_count::32, nif_comp_size::32,
        nif_orig_size::32, nif_crc::32, nif_first_ts::64, nif_first_delta::32-signed,
        nif_first_val::64, nif_ts_bits::32, nif_val_bits::32, nif_total_bits::32, _nif_ratio::64,
        _nif_creation::64, nif_flags::32, _::binary>> = nif_encoded

      <<elix_magic::64, elix_ver::16, elix_hdr_size::16, elix_count::32, elix_comp_size::32,
        elix_orig_size::32, elix_crc::32, elix_first_ts::64, elix_first_delta::32-signed,
        elix_first_val::64, elix_ts_bits::32, elix_val_bits::32, elix_total_bits::32,
        _elix_ratio::64, _elix_creation::64, elix_flags::32, _::binary>> = elixir_encoded

      assert nif_magic == elix_magic
      assert nif_ver == elix_ver
      assert nif_hdr_size == elix_hdr_size
      assert nif_count == elix_count
      assert nif_comp_size == elix_comp_size
      assert nif_orig_size == elix_orig_size
      assert nif_crc == elix_crc
      assert nif_first_ts == elix_first_ts
      assert nif_first_delta == elix_first_delta
      assert nif_first_val == elix_first_val
      assert nif_ts_bits == elix_ts_bits
      assert nif_val_bits == elix_val_bits
      assert nif_total_bits == elix_total_bits
      assert nif_flags == elix_flags
    end
  end

  describe "victoria metrics options" do
    test "VM mode with scale" do
      data = [
        {1_000_000, 36.55},
        {1_000_060, 36.72},
        {1_000_120, 36.61}
      ]

      opts = [victoria_metrics: true]
      {:ok, encoded} = Encoder.encode(data, opts)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 0.01
      end
    end

    test "VM mode with counter" do
      data = [
        {1_000_000, 100.0},
        {1_000_060, 200.0},
        {1_000_120, 350.0}
      ]

      opts = [victoria_metrics: true, is_counter: true]
      {:ok, encoded} = Encoder.encode(data, opts)
      {:ok, decoded} = Decoder.decode(encoded)

      for {{ts_orig, val_orig}, {ts_dec, val_dec}} <- Enum.zip(data, decoded) do
        assert ts_orig == ts_dec
        assert_in_delta val_orig, val_dec, 0.01
      end
    end
  end
end
