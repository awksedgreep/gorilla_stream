# Gorilla Stream Library - Performance Guide

## Table of Contents

1. [Performance Overview](#performance-overview)
2. [Benchmark Results](#benchmark-results)
3. [Optimization Strategies](#optimization-strategies)
4. [Memory Management](#memory-management)
5. [Scaling Guidelines](#scaling-guidelines)
6. [Production Tuning](#production-tuning)
7. [Realistic data generation](#realistic-data-generation)

## Performance Overview

The Gorilla Stream Library is designed for high-performance time series compression with the following characteristics:

- **Encoding Speed**: 1.7M+ points per second
- **Decoding Speed**: 50K-2M+ points per second (pattern dependent)
- **Memory Usage**: ~117 bytes per point for large datasets
- **Compression Ratios**: 2-42x depending on data patterns

### Key Performance Factors

1. **Data Patterns**: Identical/similar values compress much better
2. **Batch Size**: Optimal range is 1,000-10,000 points
3. **Memory Pressure**: Performance degrades with insufficient memory
4. **Data Ordering**: Sorted timestamps provide better compression

## Benchmark Results

### Compression Ratio by Data Pattern

| Pattern          | Compression Ratio | Original Size | Compressed Size | Reduction |
| ---------------- | ----------------- | ------------- | --------------- | --------- |
| Identical values | 0.024 (2.4%)      | 16,000 bytes  | 379 bytes       | 97.6%     |
| Step function    | 0.026 (2.6%)      | 16,000 bytes  | 412 bytes       | 97.4%     |
| Gradual increase | 0.531 (53.1%)     | 16,000 bytes  | 8,496 bytes     | 46.9%     |
| Sine wave        | 0.531 (53.1%)     | 16,000 bytes  | 8,496 bytes     | 46.9%     |
| Random walk      | 0.531 (53.1%)     | 16,000 bytes  | 8,496 bytes     | 46.9%     |
| High frequency   | 0.531 (53.1%)     | 16,000 bytes  | 8,496 bytes     | 46.9%     |

### Encoding Performance by Dataset Size

| Dataset Size  | Encode Rate (points/sec) | Encode Time | Memory Usage |
| ------------- | ------------------------ | ----------- | ------------ |
| 100 points    | 1,470,588                | 68μs        | 959 bytes    |
| 500 points    | 1,805,054                | 277μs       | 4,309 bytes  |
| 1,000 points  | 1,811,594                | 552μs       | 8,496 bytes  |
| 5,000 points  | 1,806,358                | 2.8ms       | 41,996 bytes |
| 10,000 points | 1,768,034                | 5.7ms       | 83,871 bytes |

### Decoding Performance by Dataset Size

| Dataset Size  | Decode Rate (points/sec) | Decode Time | Pattern Dependent          |
| ------------- | ------------------------ | ----------- | -------------------------- |
| 100 points    | 2,222,222                | 45μs        | Excellent for all patterns |
| 500 points    | 917,431                  | 545μs       | Good for most patterns     |
| 1,000 points  | 517,598                  | 1.9ms       | Varies by complexity       |
| 5,000 points  | 111,416                  | 45ms        | Complex patterns slower    |
| 10,000 points | 49,427                   | 202ms       | Large datasets need tuning |

### Comparison with Other Compression Methods

**Test Dataset**: 5,000 realistic sensor data points

| Method     | Compressed Size | Ratio | Encode Time | Decode Time |
| ---------- | --------------- | ----- | ----------- | ----------- |
| Gorilla    | 41,996 bytes    | 52.5% | 2.8ms       | 51ms        |
| Zlib       | 53,475 bytes    | 66.8% | 5.8ms       | 0.5ms       |
| Raw Binary | 80,007 bytes    | 100%  | 0.2ms       | 0.3ms       |

**Key Insights:**

- Gorilla achieves 21% better compression than zlib
- Encoding is 2x faster than zlib
- Decoding is slower than general-purpose compression (trade-off for specialized compression)

## Optimization Strategies

### 1. Optimal Batch Sizing

```elixir
# ✅ GOOD: Process in optimal batches
def compress_efficiently(large_dataset) do
  large_dataset
  |> Enum.chunk_every(5000)  # Sweet spot for performance
  |> Enum.map(&GorillaStream.compress/1)
end

# ❌ BAD: Processing all at once
def compress_inefficiently(large_dataset) do
  # May cause memory pressure for very large datasets
  GorillaStream.compress(large_dataset)
end
```

### 2. Data Preprocessing

```elixir
# ✅ GOOD: Sort data for optimal compression
def prepare_data(raw_data) do
  raw_data
  |> Enum.sort_by(fn {timestamp, _value} -> timestamp end)
  |> Enum.map(fn {ts, val} -> {ts, ensure_float(val)} end)
end

defp ensure_float(val) when is_number(val), do: val * 1.0
defp ensure_float(val), do: val

# ✅ GOOD: Remove outliers for better compression
def remove_outliers(data) do
  values = Enum.map(data, fn {_ts, val} -> val end)
  {q1, q3} = calculate_quartiles(values)
  iqr = q3 - q1
  lower_bound = q1 - 1.5 * iqr
  upper_bound = q3 + 1.5 * iqr

  Enum.filter(data, fn {_ts, val} ->
    val >= lower_bound and val <= upper_bound
  end)
end
```

### 3. Memory-Efficient Processing

```elixir
# ✅ GOOD: Stream processing for large datasets
def compress_stream(data_stream) do
  data_stream
  |> Stream.chunk_every(1000)
  |> Stream.map(fn batch ->
    result = GorillaStream.compress(batch)
    :erlang.garbage_collect()  # Clean up after each batch
    result
  end)
  |> Enum.to_list()
end

# ✅ GOOD: Monitor memory usage
def compress_with_monitoring(data) do
  initial_memory = :erlang.memory(:total)

  result = GorillaStream.compress(data)

  final_memory = :erlang.memory(:total)
  memory_used = final_memory - initial_memory

  Logger.info("Compressed #{length(data)} points using #{memory_used} bytes")

  result
end
```

### 4. Concurrent Processing

```elixir
# ✅ GOOD: Parallel processing of independent batches
def parallel_compress(datasets) do
  datasets
  |> Task.async_stream(
    &GorillaStream.compress/1,
    max_concurrency: System.schedulers_online()
  )
  |> Enum.map(fn {:ok, result} -> result end)
end

# ✅ GOOD: Concurrent compression of different metrics
def compress_multiple_metrics(metrics_by_type) do
  metrics_by_type
  |> Task.async_stream(fn {type, data} ->
    case GorillaStream.compress(data) do
      {:ok, compressed} -> {type, {:ok, compressed}}
      error -> {type, error}
    end
  end, max_concurrency: 4)
  |> Enum.map(fn {:ok, result} -> result end)
  |> Map.new()
end
```

## Memory Management

### Memory Usage Patterns

**Small Datasets (< 1K points):**

- Memory usage: < 1MB
- No special handling needed
- Process directly

**Medium Datasets (1K-10K points):**

- Memory usage: 1-10MB
- Monitor memory pressure
- Consider batching for very frequent operations

**Large Datasets (10K-100K points):**

- Memory usage: 10-50MB
- Always use batching
- Force garbage collection between batches
- Monitor system memory

**Very Large Datasets (100K+ points):**

- Memory usage: 50MB+
- Mandatory streaming approach
- Implement backpressure
- Consider disk-based processing

### Memory Optimization Techniques

```elixir
# 1. Garbage Collection Strategy
def compress_with_gc(data) do
  # Process in smaller chunks
  data
  |> Enum.chunk_every(2500)
  |> Enum.map(fn chunk ->
    result = GorillaStream.compress(chunk)
    :erlang.garbage_collect()
    result
  end)
end

# 2. Memory Monitoring
def monitor_memory_usage(fun) do
  :erlang.garbage_collect()
  initial = :erlang.memory(:total)

  result = fun.()

  :erlang.garbage_collect()
  final = :erlang.memory(:total)

  Logger.info("Memory delta: #{final - initial} bytes")
  result
end

# 3. Resource Pooling
defmodule CompressionPool do
  use GenServer

  def compress(data) do
    GenServer.call(__MODULE__, {:compress, data})
  end

  def handle_call({:compress, data}, _from, state) do
    # Reuse process memory space
    result = GorillaStream.compress(data)
    {:reply, result, state}
  end
end
```

## Scaling Guidelines

### Vertical Scaling (Single Machine)

**CPU Optimization:**

- Use all available cores with Task.async_stream
- Optimal concurrency: `System.schedulers_online()`
- Avoid over-subscription (more tasks than cores)

**Memory Optimization:**

- Keep batch sizes under 10K points
- Monitor memory usage continuously
- Set appropriate heap size limits

**I/O Optimization:**

- Use streaming for disk-based processing
- Implement proper buffering
- Consider compression level vs. speed trade-offs

### Horizontal Scaling (Multiple Machines)

```elixir
# Distributed processing pattern
defmodule DistributedCompression do
  def compress_across_nodes(large_dataset, nodes) do
    chunk_size = div(length(large_dataset), length(nodes))

    large_dataset
    |> Enum.chunk_every(chunk_size)
    |> Enum.zip(nodes)
    |> Task.async_stream(fn {chunk, node} ->
      :rpc.call(node, GorillaStream, :compress, [chunk])
    end, timeout: 60_000)
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```

### Production Scaling Patterns

**Pattern 1: Producer-Consumer**

```elixir
defmodule CompressionPipeline do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  def init(_opts) do
    {:producer_consumer, %{}}
  end

  def handle_events(events, _from, state) do
    compressed_events =
      events
      |> Enum.map(fn data ->
        {:ok, compressed} = GorillaStream.compress(data)
        compressed
      end)

    {:noreply, compressed_events, state}
  end
end
```

**Pattern 2: Pooled Workers**

```elixir
defmodule CompressionWorkerPool do
  use Supervisor

  def start_link(pool_size) do
    Supervisor.start_link(__MODULE__, pool_size, name: __MODULE__)
  end

  def init(pool_size) do
    children = for i <- 1..pool_size do
      Supervisor.child_spec({CompressionWorker, []}, id: {CompressionWorker, i})
    end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## Production Tuning

### Configuration Parameters

```elixir
# config/config.exs
config :gorilla_stream,
  # Optimal batch size for your data patterns
  default_batch_size: 5000,

  # Memory threshold for forcing GC
  memory_threshold_mb: 100,

  # Concurrency limits
  max_concurrent_compressions: System.schedulers_online(),

  # Enable performance monitoring
  enable_telemetry: true
```

### Performance Monitoring

```elixir
defmodule CompressionMetrics do
  def track_compression(data, fun) do
    start_time = :os.system_time(:microsecond)
    initial_memory = :erlang.memory(:total)

    result = fun.(data)

    end_time = :os.system_time(:microsecond)
    final_memory = :erlang.memory(:total)

    metrics = %{
      duration_us: end_time - start_time,
      memory_delta: final_memory - initial_memory,
      data_points: length(data),
      compression_ratio: case result do
        {:ok, compressed} -> byte_size(compressed) / (length(data) * 16)
        _ -> nil
      end
    }

    :telemetry.execute([:gorilla_stream, :compression], metrics)

    result
  end
end
```

## Realistic data generation

For performance tests that reflect real-world behavior, prefer using the realistic data generator over contrived patterns like pure sine waves.

Usage:

```elixir
alias GorillaStream.Performance.RealisticData

# Generate 5,000 realistic temperature readings, 1-minute interval, deterministic seed
data = RealisticData.generate(5_000, :temperature,
  interval: 60,
  seed: {1, 2, 3}
)

# Other supported profiles:
RealisticData.generate(10_000, :industrial_sensor)
RealisticData.generate(50_000, :server_metrics)
RealisticData.generate(2_000, :stock_prices)
RealisticData.generate(1_000, :vibration)
RealisticData.generate(20_000, :mixed_patterns)
```

Notes:

- Seeding is deterministic and isolated; it won’t affect the caller’s RNG state.
- Timestamps are monotonically increasing with the given `:interval`.
- Values are floats; integer inputs are normalized to floats internally.

### Alerting and Monitoring

```elixir
# Monitor compression performance
:telemetry.attach("compression-monitor", [:gorilla_stream, :compression], fn
  event, measurements, metadata, _config ->
    %{duration_us: duration, compression_ratio: ratio, data_points: points} = measurements

    # Alert on slow compression
    if duration > 100_000 do  # 100ms
      Logger.warning("Slow compression: #{duration}μs for #{points} points")
    end

    # Alert on poor compression
    if ratio && ratio > 0.8 do
      Logger.warning("Poor compression ratio: #{Float.round(ratio, 3)} for #{points} points")
    end

    # Send metrics to monitoring system
    MyApp.Metrics.gauge("gorilla_compression.duration_ms", duration / 1000)
    MyApp.Metrics.gauge("gorilla_compression.ratio", ratio || 0)
    MyApp.Metrics.gauge("gorilla_compression.points", points)
end, nil)
```

### Performance Testing

```elixir
defmodule PerformanceTest do
  def benchmark_data_patterns do
    patterns = [
      {"identical", generate_identical(10_000)},
      {"gradual", generate_gradual(10_000)},
      {"random", generate_random(10_000)},
      {"step", generate_step(10_000)}
    ]

    Enum.each(patterns, fn {name, data} ->
      {time, {:ok, compressed}} = :timer.tc(fn ->
        GorillaStream.compress(data)
      end)

      ratio = byte_size(compressed) / (length(data) * 16)
      rate = length(data) / (time / 1_000_000)

      IO.puts("#{name}: #{Float.round(rate, 0)} points/sec, ratio: #{Float.round(ratio, 3)}")
    end)
  end

  def load_test(duration_seconds \\ 60) do
    data = generate_gradual(1000)
    start_time = :os.system_time(:second)

    operations = Stream.repeatedly(fn ->
      GorillaStream.compress(data)
    end)
    |> Enum.take_while(fn _ ->
      :os.system_time(:second) - start_time < duration_seconds
    end)
    |> length()

    ops_per_second = operations / duration_seconds
    IO.puts("Sustained load: #{Float.round(ops_per_second, 1)} ops/sec")
  end
end
```

## Best Practices Summary

### Do's ✅

1. **Batch Appropriately**: 1K-10K points per batch
2. **Sort Data**: Timestamp-ordered data compresses better
3. **Monitor Memory**: Track memory usage in production
4. **Use Concurrency**: Parallel processing for independent batches
5. **Profile Regularly**: Measure performance with real data
6. **Handle Errors**: Always wrap compression calls in error handling
7. **Clean Up**: Force GC for long-running processes

### Don'ts ❌

1. **Don't** process unsorted data without sorting first
2. **Don't** compress tiny datasets (< 100 points) - overhead not worth it
3. **Don't** ignore memory pressure warnings
4. **Don't** use excessive concurrency (more tasks than CPU cores)
5. **Don't** compress already compressed data
6. **Don't** assume all data will compress well - profile first
7. **Don't** forget to handle decompression errors in production

## Conclusion

The Gorilla Stream Library provides excellent performance for time series compression when used correctly. Following these guidelines will help you achieve optimal performance in production environments.

Key takeaways:

- Data patterns significantly impact both compression ratio and speed
- Proper batching and memory management are crucial for large datasets
- Monitoring and profiling are essential for production deployments
- Concurrent processing can significantly improve throughput

For specific performance questions or optimization needs, consider profiling your actual data patterns and workload characteristics.
