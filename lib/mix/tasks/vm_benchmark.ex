defmodule Mix.Tasks.GorillaStream.VmBenchmark do
  use Mix.Task
  @shortdoc "Compare Gorilla, VM preprocessing, zlib, and combined variants across patterns"
  @moduledoc """
  Benchmarks compression variants on representative datasets:
  - Gorilla only
  - Gorilla + VictoriaMetrics preprocessing (auto and fixed decimals)
  - zlib only (on raw binary)
  - Gorilla -> zlib
  - Gorilla+VM -> zlib

  Examples:
      mix gorilla_stream.vm_benchmark 10000
      LOG_LEVEL=info mix gorilla_stream.vm_benchmark 50000
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

    datasets = [
      {generate_identical(count), "Identical values"},
      {generate_step(count), "Step function"},
      {generate_gauge_2dp(count), "Gauge (2dp, smooth)"},
      {generate_counter_2dp(count), "Counter (2dp, small increments)"}
    ]

    Enum.each(datasets, fn {data, label} ->
      bench_dataset(data, label)
    end)

    Logger.info("VM benchmark complete for #{count} points per dataset")
  end

  defp bench_dataset(data, label) do
    orig_bin = :erlang.term_to_binary(data)
    orig_size = byte_size(orig_bin)
    ratio = fn sz -> Float.round(sz / orig_size, 4) end
    pct = fn r -> Float.round((1.0 - r) * 100.0, 1) end

    # Gorilla only
    {t_g, {:ok, g_bin}} =
      :timer.tc(fn -> Gorilla.compress(data, zlib: false, victoria_metrics: false) end)

    g_sz = byte_size(g_bin)

    # VM auto (gauge path)
    {t_vm_auto, {:ok, vm_auto_bin}} =
      :timer.tc(fn ->
        Gorilla.compress(data,
          zlib: false,
          victoria_metrics: true,
          is_counter: false,
          scale_decimals: :auto
        )
      end)

    vm_auto_sz = byte_size(vm_auto_bin)

    # VM 2dp (gauge path)
    {t_vm_2dp, {:ok, vm_2dp_bin}} =
      :timer.tc(fn ->
        Gorilla.compress(data,
          zlib: false,
          victoria_metrics: true,
          is_counter: false,
          scale_decimals: 2
        )
      end)

    vm_2dp_sz = byte_size(vm_2dp_bin)

    # zlib only on raw data
    {t_z, z_bin} = :timer.tc(fn -> :zlib.compress(orig_bin) end)
    z_sz = byte_size(z_bin)

    # Combined: Gorilla -> zlib
    {t_gz, gz_bin} = :timer.tc(fn -> :zlib.compress(g_bin) end)
    gz_sz = byte_size(gz_bin)

    # Combined: Gorilla+VM(2dp) -> zlib
    {t_vmz, vmz_bin} = :timer.tc(fn -> :zlib.compress(vm_2dp_bin) end)
    vmz_sz = byte_size(vmz_bin)

    Logger.info("\n=== #{label} ===")
    Logger.info("Original: #{orig_size} bytes")

    Logger.info(
      "Gorilla only      : #{g_sz} bytes (ratio=#{ratio.(g_sz)}, saved=#{pct.(ratio.(g_sz))}% , enc_us=#{t_g})"
    )

    Logger.info(
      "Gorilla+VM auto   : #{vm_auto_sz} bytes (ratio=#{ratio.(vm_auto_sz)}, saved=#{pct.(ratio.(vm_auto_sz))}% , enc_us=#{t_vm_auto})"
    )

    Logger.info(
      "Gorilla+VM 2dp    : #{vm_2dp_sz} bytes (ratio=#{ratio.(vm_2dp_sz)}, saved=#{pct.(ratio.(vm_2dp_sz))}% , enc_us=#{t_vm_2dp})"
    )

    Logger.info(
      "zlib only         : #{z_sz} bytes (ratio=#{ratio.(z_sz)}, saved=#{pct.(ratio.(z_sz))}% , enc_us=#{t_z})"
    )

    Logger.info(
      "Gorilla -> zlib   : #{gz_sz} bytes (ratio=#{ratio.(gz_sz)}, saved=#{pct.(ratio.(gz_sz))}% , enc_us=#{t_g + t_gz})"
    )

    Logger.info(
      "Gorilla+VM2dp->zlb: #{vmz_sz} bytes (ratio=#{ratio.(vmz_sz)}, saved=#{pct.(ratio.(vmz_sz))}% , enc_us=#{t_vm_2dp + t_vmz})"
    )

    # Validate that VM paths round-trip
    {:ok, _} = Gorilla.decompress(vm_auto_bin)
    {:ok, _} = Gorilla.decompress(vm_2dp_bin)
  end

  # Data generators
  defp generate_identical(n) do
    base = 1_700_000_000
    for i <- 0..(n - 1), do: {base + i, 42.0}
  end

  defp generate_step(n) do
    base = 1_700_000_000
    step = max(1, div(n, 10))

    for i <- 0..(n - 1) do
      level = div(i, step)
      {base + i, level * 1.0}
    end
  end

  defp generate_gauge_2dp(n) do
    base = 1_700_000_000

    for i <- 0..(n - 1) do
      v = 100.0 + 0.01 * i + :math.sin(i / 50) * 0.1
      {base + i, Float.round(v, 2)}
    end
  end

  defp generate_counter_2dp(n) do
    base = 1_700_000_000
    increments = Stream.repeatedly(fn -> :rand.uniform(5) - 1 end) |> Enum.take(n)

    {vals, _} =
      Enum.map_reduce(increments, 1000.0, fn inc, acc ->
        v = acc + inc
        {v, v}
      end)

    for {v, i} <- Enum.with_index(vals), do: {base + i, Float.round(v + 0.01, 2)}
  end
end
