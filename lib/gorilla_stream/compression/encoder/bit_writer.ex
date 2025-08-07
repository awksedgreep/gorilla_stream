defmodule GorillaStream.Compression.Encoder.BitWriter do
  @moduledoc """
  Utility module for incrementally building a bitstring using iodata.
  It accumulates bits in a buffer and flushes complete bytes to an iolist,
  preserving performance while allowing non-byte-aligned final output.
  """

  import Bitwise

  defstruct acc: [], buf: 0, bits: 0

  @type t :: %__MODULE__{acc: iodata(), buf: non_neg_integer(), bits: non_neg_integer()}

  @doc """
  Write `size` bits from `value` into the writer.
  """
  @spec write(t(), non_neg_integer(), non_neg_integer()) :: t()
  def write(%__MODULE__{} = w, value, size) when size >= 0 do
    buf = w.buf <<< size ||| (value &&& (1 <<< size) - 1)
    flush(%{w | buf: buf, bits: w.bits + size})
  end

  @doc """
  Write the given `bits` bitstring into the writer.
  """
  @spec write_bits(t(), bitstring()) :: t()
  def write_bits(%__MODULE__{} = w, bits) when is_bitstring(bits) do
    size = bit_size(bits)
    <<value::size(size)>> = bits
    write(w, value, size)
  end

  defp flush(%__MODULE__{bits: bits} = w) when bits >= 8 do
    <<byte::8, rest::size(bits - 8)>> = <<w.buf::size(bits)>>
    flush(%{w | acc: [w.acc, byte], buf: rest, bits: bits - 8})
  end

  defp flush(w), do: w

  @doc """
  Convert the accumulated bits to a binary. Any remaining bits fewer than a byte
  are appended at the end without padding.
  """
  @spec to_binary(t()) :: bitstring()
  def to_binary(%__MODULE__{acc: acc, buf: buf, bits: bits}) do
    binary = IO.iodata_to_binary(acc)
    <<binary::binary, buf::size(bits)>>
  end
end
