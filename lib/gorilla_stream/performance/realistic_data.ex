defmodule GorillaStream.Performance.RealisticData do
  @moduledoc """
  Utilities for generating realistic time-series data for tests and benchmarks.

  Provides multiple domain-inspired profiles with configurable timestamp interval,
  base timestamp, noise, and deterministic seeding.

  Returned data shape: list of `{timestamp :: integer, value :: float}`.
  """

  @type profile ::
          :temperature
          | :industrial_sensor
          | :server_metrics
          | :stock_prices
          | :vibration
          | :mixed_patterns

  @type options :: [
          {:interval, pos_integer}
          | {:base_timestamp, integer}
          | {:seed, {non_neg_integer, non_neg_integer, non_neg_integer}}
          | {:noise, number}
        ]

  @doc """
  Generate `count` points of realistic data for a given `profile`.

  Options:
  - `:interval` seconds between points (default: 60)
  - `:base_timestamp` Unix epoch seconds for first point (default: 1_609_459_200 ~ 2020-12-31)
  - `:seed` set PRNG seed for deterministic output (default: none)
  - `:noise` base noise magnitude multiplier (profile-specific default)
  """
  @spec generate(non_neg_integer, profile, options) :: list({integer, float})
  def generate(count, profile \\ :temperature, opts \\ [])
      when is_integer(count) and count >= 0 do
    interval = Keyword.get(opts, :interval, 60)
    base_ts = Keyword.get(opts, :base_timestamp, 1_609_459_200)
    seed = Keyword.get(opts, :seed)

    gen_fun = fn ->
      case profile do
        :temperature ->
          temperature_series(count, base_ts, interval, Keyword.get(opts, :noise))

        :industrial_sensor ->
          industrial_series(count, base_ts, interval, Keyword.get(opts, :noise))

        :server_metrics ->
          server_series(count, base_ts, interval, Keyword.get(opts, :noise))

        :stock_prices ->
          stock_series(count, base_ts, interval, Keyword.get(opts, :noise))

        :vibration ->
          vibration_series(count, base_ts, interval, Keyword.get(opts, :noise))

        :mixed_patterns ->
          mixed_series(count, base_ts, interval)
      end
    end

    case seed do
      nil ->
        gen_fun.()

      {a, b, c} when is_integer(a) and is_integer(b) and is_integer(c) ->
        parent = self()
        ref = make_ref()

        spawn(fn ->
          :rand.seed(:exsplus, {a, b, c})
          send(parent, {ref, gen_fun.()})
        end)

        receive do
          {^ref, result} -> result
        end

      int when is_integer(int) ->
        parent = self()
        ref = make_ref()

        spawn(fn ->
          :rand.seed(:exsplus, {int, int * 1_103_515_245 + 12345, int * 69069 + 1})
          send(parent, {ref, gen_fun.()})
        end)

        receive do
          {^ref, result} -> result
        end

      _ ->
        gen_fun.()
    end
  end

  # Temperature with 24h sinus + small noise; occasional small steps
  defp temperature_series(0, _base, _int, _noise), do: []

  defp temperature_series(count, base, int, noise_opt) do
    noise_mag = noise_opt || 0.3
    two_pi = 2 * :math.pi()
    base_temp = 20.0

    for i <- 0..(count - 1) do
      ts = base + i * int
      # 24h cycle assuming 60s interval => period = 1440 points
      daily = 5.0 * :math.sin(two_pi * (i / 1440))
      step = if rem(i, 10_000) == 0 and i != 0, do: (:rand.uniform() - 0.5) * 1.0, else: 0.0
      noise = :rand.normal() * noise_mag
      {ts, base_temp + daily + step + noise}
    end
  end

  # Industrial sensor: slow drift + cycles + noise + spikes + maintenance resets
  defp industrial_series(0, _base, _int, _noise), do: []

  defp industrial_series(count, base, int, noise_opt) do
    noise_mag = noise_opt || 0.5
    two_pi = 2 * :math.pi()

    {data, _state} =
      Enum.map_reduce(0..(count - 1), {0.0, 0.0}, fn i, {drift, _last} ->
        ts = base + i * int
        cycle = 2.0 * :math.sin(two_pi * (i / 720))
        # very slow drift
        drift2 = drift + 0.0002
        # Random spikes
        spike = if :rand.uniform() < 0.001, do: (:rand.uniform() - 0.5) * 15.0, else: 0.0
        # Maintenance reset occasionally
        # Occasionally reset drift to simulate maintenance
        drift2 = if :rand.uniform() < 0.0005, do: 0.0, else: drift2
        base_val = 100.0 + drift2 + cycle + spike
        noise = :rand.normal() * noise_mag
        val = base_val + noise
        {{ts, val}, {drift2, val}}
      end)

    data
  end

  # Server metrics: diurnal cycle + bursty traffic (Poisson-like bursts)
  defp server_series(0, _base, _int, _noise), do: []

  defp server_series(count, base, int, _noise_opt) do
    two_pi = 2 * :math.pi()

    for i <- 0..(count - 1) do
      ts = base + i * int
      diurnal = 30.0 + 20.0 * :math.sin(two_pi * (i / 1440) - :math.pi() / 2)
      burst = if :rand.uniform() < 0.02, do: :rand.uniform() * 50.0, else: 0.0
      noise = :rand.normal() * 2.0
      {ts, max(0.0, diurnal + burst + noise)}
    end
  end

  # Stock prices: geometric random walk with volatility clustering
  defp stock_series(0, _base, _int, _noise), do: []

  defp stock_series(count, base, int, _noise) do
    volatility = fn -> if :rand.uniform() < 0.1, do: 0.05, else: 0.01 end

    {_price, acc} =
      Enum.reduce(0..(count - 1), {100.0, []}, fn i, {price, acc} ->
        ts = base + i * int
        vol = volatility.()
        # log-return
        r = vol * :rand.normal()
        new_price = max(0.01, price * :math.exp(r))
        {new_price, [{ts, new_price} | acc]}
      end)

    Enum.reverse(acc)
  end

  # Vibration: multi-sine + noise
  defp vibration_series(0, _base, _int, _noise), do: []

  defp vibration_series(count, base, int, noise_opt) do
    noise_mag = noise_opt || 0.1

    for i <- 0..(count - 1) do
      ts = base + i * int
      val = 10.0 * :math.sin(i * 0.5) + 2.0 * :math.sin(i * 1.3) + :rand.normal() * noise_mag
      {ts, val}
    end
  end

  # Mixed: concatenate segments of different profiles
  defp mixed_series(count, base, int) do
    seg = max(1, div(count, 4))

    parts = [
      temperature_series(seg, base, int, 0.2),
      vibration_series(seg, base + seg * int, int, 0.1),
      server_series(seg, base + 2 * seg * int, int, nil),
      industrial_series(count - 3 * seg, base + 3 * seg * int, int, 0.5)
    ]

    Enum.flat_map(parts, & &1)
  end
end
