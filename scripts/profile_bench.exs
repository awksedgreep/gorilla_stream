#!/usr/bin/env elixir
# Quick benchmark to compare compression across realistic profiles and sizes

Mix.install([])

base_ts = 1_609_459_200
profiles = [:temperature, :industrial_sensor, :server_metrics, :stock_prices, :vibration]
sizes = [1000, 5000, 10_000]

alias GorillaStream.Performance.RealisticData
alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

for profile <- profiles do
  IO.puts("\n=== Profile: #{profile} ===")

  for size <- sizes do
    data = RealisticData.generate(size, profile, interval: 60, base_timestamp: base_ts, seed: {1, 2, 3})

    {enc_t, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(data) end)
    {dec_t, {:ok, decoded}} = :timer.tc(fn -> Decoder.decode(compressed) end)

    ratio = byte_size(compressed) / (size * 16)
    IO.puts("size=#{size} ratio=#{Float.round(ratio, 4)} enc=#{enc_t}µs dec=#{dec_t}µs ok=#{decoded == data}")
  end
end
