defmodule GorillaStream.Compression.Gorilla.EncoderOptimized do
  @moduledoc """
  Optimized encoder for Gorilla compression.

  This implementation reduces the number of full passes over the input data
  and avoids unnecessary list reversals and extra validation passes.
  It keeps the same public API as the original encoder.
  """

  alias GorillaStream.Compression.Encoder.{DeltaEncoding, ValueCompression, BitPacking, Metadata}

  @doc """
  Encodes a stream of `{timestamp, float}` tuples using an optimized pipeline.

  The function performs a single pass over the input data to validate
  and separate timestamps and values, then delegates to the
  existing DeltaEncoding, ValueCompression, BitPacking, and
  Metadata modules.
  """
  def encode([]), do: {:ok, <<>>}

  def encode(stream) when is_list(stream) and length(stream) > 0 do
    case separate_and_validate(stream) do
      {:ok, timestamps, values} ->
        {ts_bits, ts_meta} = DeltaEncoding.encode(timestamps)
        {val_bits, val_meta} = ValueCompression.compress(values)
        {packed_binary, pack_meta} = BitPacking.pack({ts_bits, ts_meta}, {val_bits, val_meta})
        final_data = Metadata.add_metadata(packed_binary, pack_meta)
        {:ok, final_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def encode(_), do: {:error, "Invalid input data - expected list of {timestamp, float} tuples"}

  # Single pass validation and extraction.
  # Returns {:ok, timestamps, values} or {:error, reason}
  defp separate_and_validate(data) do
    case Enum.reduce_while(data, {[], [], 0}, fn
           {timestamp, value}, {ts_acc, val_acc, cnt}
           when is_integer(timestamp) and is_number(value) ->
             normalized =
               case value do
                 v when is_float(v) -> v
                 v when is_integer(v) -> v * 1.0
               end

             {:cont, {[timestamp | ts_acc], [normalized | val_acc], cnt + 1}}

           invalid_item, _acc ->
             {:halt,
              {:error,
               "Invalid data format: expected {timestamp, float} tuple, got #{inspect(invalid_item)}"}}
         end) do
      {:error, _} = err ->
        err

      {ts_rev, val_rev, _cnt} ->
        {:ok, Enum.reverse(ts_rev), Enum.reverse(val_rev)}
    end
  end
end
