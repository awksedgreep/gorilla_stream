defmodule GorillaStream.Compression.Enhancements do
  @moduledoc """
  Optional preprocessing helpers inspired by VictoriaMetrics to improve
  compressibility on top of Gorilla.

  Functions:
  - scale_floats_to_ints/2: scales list of numbers by 10^N (auto or explicit), returning {ints, N}
  - delta_encode_counter/1 and delta_decode_counter/1: encode/decode monotonic counters
  - monotonic_non_decreasing?/1: simple monotonic check
  """

  @type scale :: non_neg_integer() | :auto

  @doc """
  Scales numeric values by 10^N to integers. If N is :auto, detect the max decimals
  across the list (capped at 6 to avoid float artifacts).
  """
  @spec scale_floats_to_ints([number()], scale()) :: {[integer()], non_neg_integer()}
  def scale_floats_to_ints(values, :auto) do
    n = detect_scale(values)
    scale_floats_to_ints(values, n)
  end

  def scale_floats_to_ints(values, n) when is_integer(n) and n >= 0 do
    scale = pow10(n)
    ints = Enum.map(values, fn v -> trunc(Float.round(v * 1.0 * scale, 0)) end)
    {ints, n}
  end

  @doc """
  Detects a reasonable scale (number of decimal digits) for the given values.
  Uses a decimal-string approach and caps at 6.
  """
  @spec detect_scale([number()]) :: non_neg_integer()
  def detect_scale(values) do
    values
    |> Enum.reduce(0, fn v, acc -> max(acc, decimals_for(v)) end)
    |> min(6)
  end

  defp decimals_for(v) when is_integer(v), do: 0

  defp decimals_for(v) do
    s = :erlang.float_to_binary(v * 1.0, [:compact, {:decimals, 10}])

    case String.split(s, ".") do
      [_i, frac] -> String.trim_trailing(frac, "0") |> String.length()
      _ -> 0
    end
  end

  @doc """
  Delta-encodes a monotonic counter series. Keeps the first element as absolute
  and replaces subsequent elements with differences.
  """
  @spec delta_encode_counter([number()]) :: [number()]
  def delta_encode_counter([]), do: []

  def delta_encode_counter([h | t]) do
    {deltas, _} = Enum.reduce(t, {[h], h}, fn x, {acc, prev} -> {[x - prev | acc], x} end)
    Enum.reverse(deltas)
  end

  @doc """
  Decodes a delta-encoded counter series back to absolutes.
  """
  @spec delta_decode_counter([number()]) :: [number()]
  def delta_decode_counter([]), do: []

  def delta_decode_counter([h | t]) do
    {vals, _} =
      Enum.reduce(t, {[h], h}, fn d, {acc, prev} ->
        v = prev + d
        {[v | acc], v}
      end)

    Enum.reverse(vals)
  end

  @doc """
  Simple check for non-decreasing monotonicity.
  """
  @spec monotonic_non_decreasing?([number()]) :: boolean()
  def monotonic_non_decreasing?([]), do: true
  def monotonic_non_decreasing?([_]), do: true

  def monotonic_non_decreasing?([a, b | rest]) do
    if b < a, do: false, else: monotonic_non_decreasing?([b | rest])
  end

  defp pow10(0), do: 1

  defp pow10(n) when n > 0 do
    :math.pow(10, n) |> round()
  end
end
