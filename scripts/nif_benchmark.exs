alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}
alias GorillaStream.Compression.Gorilla.NIF

defmodule Bench do
  def measure(label, fun, iterations) do
    # Warm up
    fun.()

    {elapsed_us, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations, do: fun.()
      end)

    per_call_us = elapsed_us / iterations
    ips = 1_000_000 / per_call_us

    {per_call_us, ips, label}
  end

  def compare(label, nif_fun, elixir_fun, iterations) do
    {nif_us, nif_ips, _} = measure("NIF", nif_fun, iterations)
    {elix_us, elix_ips, _} = measure("Elixir", elixir_fun, iterations)
    speedup = elix_us / nif_us

    IO.puts("  #{label}")
    IO.puts("    NIF:    #{Float.round(nif_us, 1)} µs/call  (#{Float.round(nif_ips, 0)} ops/s)")
    IO.puts("    Elixir: #{Float.round(elix_us, 1)} µs/call  (#{Float.round(elix_ips, 0)} ops/s)")
    IO.puts("    Speedup: #{Float.round(speedup, 1)}x")
    IO.puts("")
  end
end

sizes = [10, 100, 1_000, 10_000]

datasets =
  for n <- sizes do
    base_ts = 1_700_000_000
    data = for i <- 0..(n - 1), do: {base_ts + i * 60, 20.0 + :math.sin(i / 10.0) * 5.0}
    {n, data}
  end

IO.puts("=== Gorilla NIF vs Elixir Benchmark ===\n")

# Warm up NIF
{:ok, _} = NIF.nif_gorilla_encode([{1, 1.0}], %{})
{:ok, _} = NIF.nif_gorilla_decode(elem(NIF.nif_gorilla_encode([{1, 1.0}], %{}), 1))

IO.puts("--- ENCODE ---")
for {n, data} <- datasets do
  iterations = max(10, div(50_000, n))
  Bench.compare(
    "#{n} points (#{iterations} iterations)",
    fn -> NIF.nif_gorilla_encode(data, %{}) end,
    fn -> Encoder.encode_elixir(data, []) end,
    iterations
  )
end

IO.puts("--- DECODE ---")
for {n, data} <- datasets do
  {:ok, encoded} = Encoder.encode_elixir(data, [])
  iterations = max(10, div(50_000, n))
  Bench.compare(
    "#{n} points (#{iterations} iterations)",
    fn -> NIF.nif_gorilla_decode(encoded) end,
    fn -> Decoder.decode_elixir(encoded) end,
    iterations
  )
end
