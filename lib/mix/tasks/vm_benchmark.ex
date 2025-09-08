defmodule Mix.Tasks.GorillaStream.VmBenchmark do
  use Mix.Task
  @shortdoc "Compare compression with and without VictoriaMetrics preprocessing"
  @moduledoc """
  Runs a simple benchmark comparing Gorilla alone vs Gorilla+VictoriaMetrics preprocessing.

  Examples:
      mix gorilla_stream.vm_benchmark 10000
  """

  require Logger
  alias GorillaStream.Compression.Gorilla

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    count =
      case args do
        [n] -> String.to_integer(n)
        _ -> 10_000
      end

    data = generate_gauge(count)

    # Baseline (Gorilla only)
    {t1, {:ok, bin1}} = :timer.tc(fn -> Gorilla.compress(data, zlib: false, victoria_metrics: false) end)
    size1 = byte_size(bin1)

    # VM preprocessing (scaling only)
    {t2, {:ok, bin2}} = :timer.tc(fn -> Gorilla.compress(data, zlib: false, victoria_metrics: true, is_counter: false, scale_decimals: :auto) end)
    size2 = byte_size(bin2)

    ratio = fn sz, orig -> Float.round(sz / orig, 4) end

    orig_size = byte_size(:erlang.term_to_binary(data))

    Logger.info("[Gauge] Gorilla only: size=#{size1} (ratio=#{ratio.(size1, orig_size)}), encode_time_us=#{t1}")
    Logger.info("[Gauge] Gorilla+VM:  size=#{size2} (ratio=#{ratio.(size2, orig_size)}), encode_time_us=#{t2}")

    # Verify round-trip for VM path
    {:ok, back} = Gorilla.decompress(bin2)
    _ = back

    # Counter dataset
    counter = generate_counter(count)
    {ct1, {:ok, cbin1}} = :timer.tc(fn -> Gorilla.compress(counter, zlib: false, victoria_metrics: false) end)
    csize1 = byte_size(cbin1)

    {ct2, {:ok, cbin2}} = :timer.tc(fn -> Gorilla.compress(counter, zlib: false, victoria_metrics: true, is_counter: true, scale_decimals: :auto) end)
    csize2 = byte_size(cbin2)

    corig_size = byte_size(:erlang.term_to_binary(counter))

    Logger.info("[Counter] Gorilla only: size=#{csize1} (ratio=#{ratio.(csize1, corig_size)}), encode_time_us=#{ct1}")
    Logger.info("[Counter] Gorilla+VM:  size=#{csize2} (ratio=#{ratio.(csize2, corig_size)}), encode_time_us=#{ct2}")

    {:ok, _} = Gorilla.decompress(cbin2)

    Logger.info("VM benchmark complete for #{count} points")
  end

  defp generate_gauge(n) do
    base = 1_700_000_000
    for i <- 0..(n - 1) do
      # Smoothly varying gauge with decimals
      {base + i, 100.0 + 0.01 * i + :math.sin(i / 50) * 0.1}
    end
  end

  defp generate_counter(n) do
    base = 1_700_000_000
    increments = Stream.repeatedly(fn -> :rand.uniform(10) - 1 end) |> Enum.take(n)
    {vals, _} =
      Enum.map_reduce(increments, 1_000.0, fn inc, acc ->
        v = acc + inc
        {v, v}
      end)
    for {v, i} <- Enum.with_index(vals), do: {base + i, v + 0.01}
  end
end

