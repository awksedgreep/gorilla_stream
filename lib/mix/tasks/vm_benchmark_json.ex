defmodule Mix.Tasks.GorillaStream.VmBenchmarkJson do
  use Mix.Task
  @shortdoc "Outputs JSON summary comparing Gorilla vs Gorilla+VictoriaMetrics preprocessing"
  @moduledoc """
  Produces a JSON summary for POC comparisons. You can write to a file or log to stdout via Logger.

  Examples:
      mix gorilla_stream.vm_benchmark_json --count 10000 --out vm_summary.json
      mix gorilla_stream.vm_benchmark_json 20000
  """

  require Logger
  alias GorillaStream.Compression.Gorilla

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        switches: [count: :integer, out: :string],
        aliases: [n: :count, o: :out]
      )

    count =
      cond do
        is_integer(opts[:count]) ->
          opts[:count]

        match?([_ | _], positional) and integer_string?(hd(positional)) ->
          String.to_integer(hd(positional))

        true ->
          10_000
      end

    out_path = opts[:out]

    gauge = generate_gauge(count)
    counter = generate_counter(count)

    # Gauge baseline and VM
    {g_t1, {:ok, g_bin1}} =
      :timer.tc(fn -> Gorilla.compress(gauge, zlib: false, victoria_metrics: false) end)

    g_size1 = byte_size(g_bin1)

    {g_t2, {:ok, g_bin2}} =
      :timer.tc(fn ->
        Gorilla.compress(gauge,
          zlib: false,
          victoria_metrics: true,
          is_counter: false,
          scale_decimals: :auto
        )
      end)

    g_size2 = byte_size(g_bin2)
    g_orig = byte_size(:erlang.term_to_binary(gauge))

    # Counter baseline and VM
    {c_t1, {:ok, c_bin1}} =
      :timer.tc(fn -> Gorilla.compress(counter, zlib: false, victoria_metrics: false) end)

    c_size1 = byte_size(c_bin1)

    {c_t2, {:ok, c_bin2}} =
      :timer.tc(fn ->
        Gorilla.compress(counter,
          zlib: false,
          victoria_metrics: true,
          is_counter: true,
          scale_decimals: :auto
        )
      end)

    c_size2 = byte_size(c_bin2)
    c_orig = byte_size(:erlang.term_to_binary(counter))

    # Verify round-trips (will raise if failure)
    {:ok, _} = Gorilla.decompress(g_bin2)
    {:ok, _} = Gorilla.decompress(c_bin2)

    summary = %{
      count: count,
      gauge: %{
        original_size: g_orig,
        baseline_size: g_size1,
        vm_size: g_size2,
        baseline_ratio: ratio(g_size1, g_orig),
        vm_ratio: ratio(g_size2, g_orig),
        baseline_encode_time_us: g_t1,
        vm_encode_time_us: g_t2
      },
      counter: %{
        original_size: c_orig,
        baseline_size: c_size1,
        vm_size: c_size2,
        baseline_ratio: ratio(c_size1, c_orig),
        vm_ratio: ratio(c_size2, c_orig),
        baseline_encode_time_us: c_t1,
        vm_encode_time_us: c_t2
      }
    }

    json = encode_json(summary)

    case out_path do
      nil ->
        Logger.info(json)

      path ->
        case File.write(path, json <> "\n") do
          :ok -> Logger.info("Wrote JSON summary to #{path}")
          {:error, reason} -> Logger.error("Failed to write JSON summary: #{inspect(reason)}")
        end
    end
  end

  defp integer_string?(s) when is_binary(s) do
    case Integer.parse(s) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp ratio(sz, orig) when orig > 0, do: Float.round(sz / orig, 6)
  defp ratio(_sz, _orig), do: 0.0

  # Simple JSON encoder for maps/lists with numbers/strings/booleans (no external deps)
  defp encode_json(value), do: encode_value(value)

  defp encode_value(v) when is_map(v) do
    entries =
      v
      |> Enum.map(fn {k, val} ->
        key = to_string(k)
        "\"#{escape(key)}\":#{encode_value(val)}"
      end)
      |> Enum.join(",")

    "{" <> entries <> "}"
  end

  defp encode_value(v) when is_list(v) do
    items = v |> Enum.map(&encode_value/1) |> Enum.join(",")
    "[" <> items <> "]"
  end

  defp encode_value(v) when is_binary(v), do: "\"" <> escape(v) <> "\""
  defp encode_value(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(nil), do: "null"

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp generate_gauge(n) do
    base = 1_700_000_000

    for i <- 0..(n - 1) do
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
