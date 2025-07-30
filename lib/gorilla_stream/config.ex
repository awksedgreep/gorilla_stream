defmodule GorillaStream.Config do
  @moduledoc """
  Configuration and auto-tuning utilities for GorillaStream.

  Helps users optimize compression settings based on their data patterns
  and performance requirements.
  """

  alias GorillaStream.Compression.Gorilla.{Encoder, Decoder}

  @doc """
  Analyzes a sample of data and recommends optimal settings.

  ## Examples

      iex> sample_data = generate_sensor_data(1000)
      iex> GorillaStream.Config.analyze_and_recommend(sample_data)
      %{
        recommended_chunk_size: 5000,
        expected_compression_ratio: 0.52,
        use_zlib: false,
        memory_per_chunk_mb: 2.3,
        estimated_throughput: 1_800_000
      }
  """
  def analyze_and_recommend(sample_data, opts \\ []) do
    target_latency_ms = Keyword.get(opts, :target_latency_ms, 100)
    memory_limit_mb = Keyword.get(opts, :memory_limit_mb, 100)

    # Test compression on sample
    {encode_time, {:ok, compressed}} = :timer.tc(fn -> Encoder.encode(sample_data) end)
    {decode_time, _} = :timer.tc(fn -> Decoder.decode(compressed) end)

    sample_size = length(sample_data)
    compression_ratio = byte_size(compressed) / (sample_size * 16)
    encode_rate = sample_size / (encode_time / 1_000_000)
    decode_rate = sample_size / (decode_time / 1_000_000)

    # Estimate optimal chunk size based on target latency
    target_latency_us = target_latency_ms * 1000

    optimal_chunk_size =
      min(
        trunc(target_latency_us * encode_rate / 1_000_000),
        trunc(memory_limit_mb * 1024 * 1024 / (sample_size / length(sample_data) * 16))
      )

    # Test if zlib would be beneficial
    zlib_compressed = :zlib.compress(compressed)
    zlib_benefit = (byte_size(compressed) - byte_size(zlib_compressed)) / byte_size(compressed)

    %{
      data_characteristics: analyze_data_patterns(sample_data),
      performance_metrics: %{
        compression_ratio: compression_ratio,
        encode_rate_points_per_sec: trunc(encode_rate),
        decode_rate_points_per_sec: trunc(decode_rate),
        encode_time_us: encode_time,
        decode_time_us: decode_time
      },
      recommendations: %{
        chunk_size: max(1000, optimal_chunk_size),
        use_zlib: zlib_benefit > 0.1,
        memory_per_chunk_mb: optimal_chunk_size * 16 / (1024 * 1024),
        estimated_throughput_points_per_sec: trunc(encode_rate),
        parallel_workers: recommend_concurrency(encode_rate, target_latency_ms)
      },
      zlib_analysis: %{
        additional_compression: zlib_benefit,
        recommended: zlib_benefit > 0.1
      }
    }
  end

  @doc """
  Analyzes data patterns to understand compression potential.
  """
  def analyze_data_patterns(data) do
    if length(data) < 2 do
      %{pattern: :insufficient_data}
    else
      timestamps = Enum.map(data, fn {ts, _} -> ts end)
      values = Enum.map(data, fn {_, val} -> val end)

      timestamp_analysis = analyze_timestamps(timestamps)
      value_analysis = analyze_values(values)

      %{
        timestamp_pattern: timestamp_analysis,
        value_pattern: value_analysis,
        overall_pattern: classify_overall_pattern(timestamp_analysis, value_analysis)
      }
    end
  end

  defp analyze_timestamps(timestamps) do
    deltas =
      Enum.zip(timestamps, tl(timestamps))
      |> Enum.map(fn {a, b} -> b - a end)

    delta_variance = calculate_variance(deltas)
    mean_delta = Enum.sum(deltas) / length(deltas)

    pattern =
      cond do
        delta_variance < mean_delta * 0.01 -> :regular
        delta_variance < mean_delta * 0.1 -> :mostly_regular
        true -> :irregular
      end

    %{
      pattern: pattern,
      mean_interval: mean_delta,
      variance: delta_variance,
      regularity_score: 1 / (1 + delta_variance / max(mean_delta, 1))
    }
  end

  defp analyze_values(values) do
    value_changes =
      Enum.zip(values, tl(values))
      |> Enum.map(fn {a, b} -> abs(b - a) end)

    mean_change = Enum.sum(value_changes) / length(value_changes)
    max_value = Enum.max(values)
    min_value = Enum.min(values)

    pattern =
      cond do
        mean_change < (max_value - min_value) * 0.01 -> :very_stable
        mean_change < (max_value - min_value) * 0.1 -> :stable
        mean_change < (max_value - min_value) * 0.5 -> :moderate_changes
        true -> :highly_variable
      end

    %{
      pattern: pattern,
      mean_change: mean_change,
      range: max_value - min_value,
      stability_score: 1 / (1 + mean_change / max(max_value - min_value, 1))
    }
  end

  defp classify_overall_pattern(timestamp_analysis, value_analysis) do
    case {timestamp_analysis.pattern, value_analysis.pattern} do
      {:regular, :very_stable} -> :optimal_for_gorilla
      {:regular, :stable} -> :excellent_for_gorilla
      {:mostly_regular, :stable} -> :good_for_gorilla
      {:mostly_regular, :moderate_changes} -> :fair_for_gorilla
      _ -> :challenging_for_gorilla
    end
  end

  defp calculate_variance(numbers) do
    mean = Enum.sum(numbers) / length(numbers)

    variance =
      Enum.map(numbers, fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(numbers))

    variance
  end

  defp recommend_concurrency(encode_rate, target_latency_ms) do
    # Recommend parallel workers based on encode rate and latency requirements
    if encode_rate > 1_000_000 and target_latency_ms > 50 do
      min(System.schedulers_online(), 4)
    else
      1
    end
  end

  @doc """
  Provides a simple benchmark suite for user's specific data.
  """
  def benchmark_data(data, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 10)

    # Warmup
    {:ok, _} = Encoder.encode(data)

    # Benchmark encoding
    encode_times =
      for _ <- 1..iterations do
        {time, {:ok, _}} = :timer.tc(fn -> Encoder.encode(data) end)
        time
      end

    # Benchmark decoding
    {:ok, compressed} = Encoder.encode(data)

    decode_times =
      for _ <- 1..iterations do
        {time, {:ok, _}} = :timer.tc(fn -> Decoder.decode(compressed) end)
        time
      end

    %{
      encode_stats: calculate_stats(encode_times),
      decode_stats: calculate_stats(decode_times),
      compression_ratio: byte_size(compressed) / (length(data) * 16),
      points_per_second: %{
        encode: length(data) / (Enum.sum(encode_times) / length(encode_times) / 1_000_000),
        decode: length(data) / (Enum.sum(decode_times) / length(decode_times) / 1_000_000)
      }
    }
  end

  defp calculate_stats(times) do
    sorted = Enum.sort(times)
    mean = Enum.sum(times) / length(times)
    median = Enum.at(sorted, div(length(times), 2))
    min_time = Enum.min(times)
    max_time = Enum.max(times)

    %{
      mean_us: trunc(mean),
      median_us: median,
      min_us: min_time,
      max_us: max_time,
      std_dev_us: trunc(:math.sqrt(calculate_variance(times)))
    }
  end
end
