# Gorilla Stream Library - Troubleshooting Guide

## Table of Contents

1. [Common Issues](#common-issues)
2. [Error Messages](#error-messages)
3. [Performance Problems](#performance-problems)
4. [Memory Issues](#memory-issues)
5. [Data Quality Problems](#data-quality-problems)
6. [Debugging Tools](#debugging-tools)
7. [FAQ](#faq)

## Common Issues

### Issue: Compression Fails with Format Errors

**Symptoms:**

- `{:error, "Invalid data format: expected {timestamp, float} tuple"}`
- `{:error, "Invalid input data"}`

**Causes:**

- Wrong data structure passed to compression function
- Mixed data types in timestamps or values
- Non-numeric values in data

**Solutions:**

```elixir
# ❌ Wrong format
bad_data = [1.23, 2.34, 3.45]  # Plain numbers, not tuples
bad_data = [{1609459200, "23.5"}]  # String value instead of number
bad_data = [{"2023-01-01", 23.5}]  # String timestamp

# ✅ Correct format
good_data = [{1609459200, 23.5}, {1609459260, 23.7}]

# Fix data format before compression
def fix_data_format(raw_data) do
  Enum.map(raw_data, fn
    {timestamp, value} when is_integer(timestamp) and is_number(value) ->
      {timestamp, value * 1.0}  # Ensure float

    {timestamp, value} when is_binary(timestamp) ->
      # Convert string timestamp to integer
      ts = String.to_integer(timestamp)
      val = if is_binary(value), do: String.to_float(value), else: value * 1.0
      {ts, val}

    invalid ->
      raise ArgumentError, "Invalid data point: #{inspect(invalid)}"
  end)
end
```

### Issue: Poor Compression Ratios

**Symptoms:**

- Compression ratio > 0.8 (less than 20% compression)
- Compressed data larger than expected

**Diagnosis:**

```elixir
# Check estimated compression ratio first
{:ok, estimated_ratio} = GorillaStream.Compression.Gorilla.Encoder.estimate_compression_ratio(data)

cond do
  estimated_ratio > 0.8 ->
    IO.puts("Data pattern not suitable for Gorilla compression")
  estimated_ratio > 0.6 ->
    IO.puts("Moderate compression expected")
  true ->
    IO.puts("Good compression expected")
end
```

**Solutions:**

1. **Analyze your data pattern:**

```elixir
def analyze_data_pattern(data) do
  values = Enum.map(data, fn {_ts, val} -> val end)

  # Check for identical values
  unique_values = Enum.uniq(values) |> length()
  identical_ratio = unique_values / length(values)

  # Check for gradual changes
  differences = values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> abs(b - a) end)
  avg_difference = Enum.sum(differences) / length(differences)

  %{
    total_points: length(data),
    unique_values: unique_values,
    identical_ratio: identical_ratio,
    avg_difference: avg_difference
  }
end
```

2. **Preprocess data for better compression:**

```elixir
# Remove noise/outliers
def smooth_data(data, window_size \\ 3) do
  data
  |> Enum.chunk_every(window_size, 1, :discard)
  |> Enum.map(fn chunk ->
    {ts, _} = hd(chunk)
    avg_value = chunk |> Enum.map(fn {_, v} -> v end) |> Enum.sum() |> div(length(chunk))
    {ts, avg_value}
  end)
end

# Round to reduce precision if appropriate
def round_values(data, precision \\ 2) do
  Enum.map(data, fn {ts, val} ->
    {ts, Float.round(val, precision)}
  end)
end
```

### Issue: Memory Usage Too High

**Symptoms:**

- Process memory grows during compression
- System becomes slow or unresponsive
- Out of memory errors

**Diagnosis:**

```elixir
def diagnose_memory_usage(data) do
  :erlang.garbage_collect()
  initial_memory = :erlang.memory()

  # Test compression
  {time, result} = :timer.tc(fn ->
    GorillaStream.compress(data)
  end)

  :erlang.garbage_collect()
  final_memory = :erlang.memory()

  memory_delta = final_memory[:total] - initial_memory[:total]
  memory_per_point = memory_delta / length(data)

  %{
    data_points: length(data),
    compression_time_us: time,
    memory_delta: memory_delta,
    memory_per_point: memory_per_point,
    result: result
  }
end
```

**Solutions:**

1. **Use batching for large datasets:**

```elixir
def compress_large_dataset(data, batch_size \\ 5000) do
  data
  |> Enum.chunk_every(batch_size)
  |> Enum.map(fn batch ->
    result = GorillaStream.compress(batch)
    :erlang.garbage_collect()  # Force cleanup after each batch
    result
  end)
end
```

2. **Stream processing:**

```elixir
def stream_compress(data_stream) do
  data_stream
  |> Stream.chunk_every(1000)
  |> Stream.map(fn batch ->
    {:ok, compressed} = GorillaStream.compress(batch)
    compressed
  end)
  |> Enum.to_list()
end
```

### Issue: Slow Performance

**Symptoms:**

- Compression takes longer than expected
- Encoding rate < 100K points/sec
- System becomes unresponsive during compression

**Diagnosis:**

```elixir
def benchmark_performance(data) do
  # Test encoding performance
  {encode_time, {:ok, compressed}} = :timer.tc(fn ->
    GorillaStream.compress(data)
  end)

  # Test decoding performance
  {decode_time, {:ok, _decompressed}} = :timer.tc(fn ->
    GorillaStream.decompress(compressed)
  end)

  encode_rate = length(data) / (encode_time / 1_000_000)
  decode_rate = length(data) / (decode_time / 1_000_000)

  %{
    data_points: length(data),
    encode_rate_per_sec: encode_rate,
    decode_rate_per_sec: decode_rate,
    encode_time_ms: encode_time / 1000,
    decode_time_ms: decode_time / 1000
  }
end
```

**Solutions:**

1. **Optimize batch size:**

```elixir
def find_optimal_batch_size(data) do
  batch_sizes = [500, 1000, 2500, 5000, 10000]

  results = Enum.map(batch_sizes, fn size ->
    sample_data = Enum.take(data, size)

    {time, _result} = :timer.tc(fn ->
      GorillaStream.compress(sample_data)
    end)

    rate = size / (time / 1_000_000)
    {size, rate}
  end)

  {optimal_size, _best_rate} = Enum.max_by(results, fn {_size, rate} -> rate end)
  optimal_size
end
```

2. **Use concurrent processing:**

```elixir
def concurrent_compress(data_batches) do
  data_batches
  |> Task.async_stream(
    &GorillaStream.compress/1,
    max_concurrency: System.schedulers_online()
  )
  |> Enum.map(fn {:ok, result} -> result end)
end
```

## Error Messages

### "Invalid input data"

**Cause:** Non-list input passed to compression function

**Fix:**

```elixir
# ❌ Wrong
GorillaStream.compress("not a list")
GorillaStream.compress(%{data: "map"})

# ✅ Correct
GorillaStream.compress([{1609459200, 23.5}])
```

### "Invalid data format: expected {timestamp, float} tuple"

**Cause:** Wrong tuple structure or data types

**Fix:**

```elixir
# ❌ Wrong formats
[{1, 2, 3}]  # Too many elements
[{1}]        # Too few elements
[{"string", 2.0}]  # String timestamp
[{1, "string"}]    # String value

# ✅ Correct format
[{1609459200, 23.5}]  # Integer timestamp, numeric value
```

### "Insufficient data for initial values"

**Cause:** Corrupted or truncated compressed data during decompression

**Fix:**

```elixir
def safe_decompress(compressed_data, use_zlib \\ false) do
  case GorillaStream.decompress(compressed_data, use_zlib) do
    {:ok, data} -> {:ok, data}
    {:error, "Insufficient data for initial values"} ->
      Logger.error("Compressed data appears to be corrupted or truncated")
      {:error, :corrupted_data}
    {:error, reason} -> {:error, reason}
  end
end
```

### "Timestamp decoding failed"

**Cause:** Corrupted timestamp data in compressed binary

**Fix:**

```elixir
def validate_compressed_data(compressed_data) do
  # Check minimum size
  if byte_size(compressed_data) < 32 do
    {:error, "Compressed data too small"}
  else
    # Try to extract header
    case compressed_data do
      <<magic::64, version::16, _rest::binary>> ->
        if magic == 0x474F52494C4C41 do  # "GORILLA"
          :ok
        else
          {:error, "Invalid magic number"}
        end
      _ ->
        {:error, "Invalid header format"}
    end
  end
end
```

## Performance Problems

### Compression Rate Too Slow

**Expected:** 1M+ points/sec  
**Actual:** < 100K points/sec

**Debug Steps:**

1. **Check data size:**

```elixir
data_size_mb = length(data) * 16 / 1_048_576
if data_size_mb > 100 do
  IO.puts("Large dataset detected: #{data_size_mb}MB")
  # Consider batching
end
```

2. **Profile memory usage:**

```elixir
{:ok, _} = :eprof.start()
:eprof.start_profiling([self()])

GorillaStream.compress(data)

:eprof.stop_profiling()
:eprof.analyze()
```

3. **Check system resources:**

```elixir
memory_info = :erlang.memory()
IO.inspect(memory_info, label: "Memory usage")

process_info = :erlang.process_info(self(), [:memory, :heap_size])
IO.inspect(process_info, label: "Process info")
```

### High Memory Usage

**Expected:** < 200 bytes/point  
**Actual:** > 500 bytes/point

**Solutions:**

1. **Force garbage collection:**

```elixir
def compress_with_gc(data) do
  :erlang.garbage_collect()
  result = GorillaStream.Compression.Gorilla.compress(data, false)
  :erlang.garbage_collect()
  result
end
```

2. **Use smaller batches:**

```elixir
def memory_efficient_compress(data) do
  data
  |> Enum.chunk_every(1000)  # Smaller batches
  |> Enum.map(&compress_with_gc/1)
end
```

3. **Monitor memory growth:**

```elixir
def compress_with_monitoring(data) do
  Process.flag(:monitor_memory, true)

  result = GorillaStream.Compression.Gorilla.compress(data, false)

  receive do
    {:memory_high, _pid} ->
      Logger.warning("High memory usage during compression")
  after 0 ->
    :ok
  end

  result
end
```

## Memory Issues

### Memory Leaks

**Symptoms:**

- Memory usage grows over time
- System becomes slower after many operations
- Eventually runs out of memory

**Detection:**

```elixir
defmodule MemoryLeakDetector do
  def run_leak_test(iterations \\ 100) do
    initial_memory = :erlang.memory(:total)
    data = generate_test_data(1000)

    for i <- 1..iterations do
      {:ok, _compressed} = GorillaStream.compress(data)

      if rem(i, 10) == 0 do
        current_memory = :erlang.memory(:total)
        growth = current_memory - initial_memory
        IO.puts("Iteration #{i}: Memory growth: #{growth} bytes")
      end
    end

    :erlang.garbage_collect()
    final_memory = :erlang.memory(:total)
    total_growth = final_memory - initial_memory

    if total_growth > 10_000_000 do  # 10MB
      IO.puts("⚠️  Potential memory leak detected: #{total_growth} bytes")
    else
      IO.puts("✅ No significant memory leak detected")
    end
  end

  defp generate_test_data(count) do
    for i <- 1..count do
      {1609459200 + i, 100.0 + i * 0.1}
    end
  end
end
```

**Solutions:**

```elixir
# Explicit cleanup after compression
def compress_and_cleanup(data) do
  result = GorillaStream.compress(data)
  :erlang.garbage_collect()
  result
end

# Use separate processes to isolate memory
def compress_in_separate_process(data) do
  parent = self()

  spawn_link(fn ->
    result = GorillaStream.compress(data)
    send(parent, {:compression_result, result})
  end)

  receive do
    {:compression_result, result} -> result
  after 60_000 ->
    {:error, :timeout}
  end
end
```

### Out of Memory Errors

**Solutions:**

1. **Implement backpressure:**

```elixir
defmodule BackpressureCompressor do
  use GenServer

  def start_link(max_memory_mb \\ 100) do
    GenServer.start_link(__MODULE__, max_memory_mb, name: __MODULE__)
  end

  def compress(data) do
    GenServer.call(__MODULE__, {:compress, data}, 60_000)
  end

  def init(max_memory_mb) do
    {:ok, %{max_memory: max_memory_mb * 1_048_576}}
  end

  def handle_call({:compress, data}, _from, state) do
    current_memory = :erlang.memory(:total)

    if current_memory > state.max_memory do
      :erlang.garbage_collect()
      :timer.sleep(100)  # Brief pause to allow GC
    end

    result = GorillaStream.compress(data)
    {:reply, result, state}
  end
end
```

2. **Disk-based processing for very large datasets:**

```elixir
def compress_to_disk(data, output_file) do
  File.open!(output_file, [:write, :binary], fn file ->
    data
    |> Enum.chunk_every(1000)
    |> Enum.each(fn batch ->
      {:ok, compressed} = GorillaStream.compress(batch)
      IO.binwrite(file, <<byte_size(compressed)::32, compressed::binary>>)
    end)
  end)
end
```

## Data Quality Problems

### NaN and Infinity Values

**Problem:** Data contains NaN or infinity values

**Detection:**

```elixir
def check_for_special_values(data) do
  special_values = Enum.filter(data, fn {_ts, val} ->
    not is_finite(val) or is_nan(val)
  end)

  if length(special_values) > 0 do
    IO.puts("⚠️  Found #{length(special_values)} special values:")
    Enum.each(special_values, fn {ts, val} ->
      IO.puts("  Timestamp #{ts}: #{inspect(val)}")
    end)
  end

  special_values
end

defp is_finite(val) when is_float(val) do
  val != :infinity and val != :neg_infinity
end
defp is_finite(_), do: true

defp is_nan(val) when is_float(val), do: val != val
defp is_nan(_), do: false
```

**Solutions:**

```elixir
def clean_special_values(data, strategy \\ :remove) do
  case strategy do
    :remove ->
      Enum.filter(data, fn {_ts, val} ->
        is_finite(val) and not is_nan(val)
      end)

    :interpolate ->
      interpolate_special_values(data)

    :replace_with_zero ->
      Enum.map(data, fn {ts, val} ->
        if is_finite(val) and not is_nan(val) do
          {ts, val}
        else
          {ts, 0.0}
        end
      end)
  end
end
```

### Unsorted Timestamps

**Problem:** Data is not sorted by timestamp

**Detection:**

```elixir
def check_timestamp_order(data) do
  timestamps = Enum.map(data, fn {ts, _} -> ts end)
  sorted_timestamps = Enum.sort(timestamps)

  if timestamps != sorted_timestamps do
    IO.puts("⚠️  Data is not sorted by timestamp")

    # Find first out-of-order point
    Enum.zip(timestamps, sorted_timestamps)
    |> Enum.with_index()
    |> Enum.find(fn {{original, sorted}, _index} -> original != sorted end)
    |> case do
      {{original, sorted}, index} ->
        IO.puts("  First disorder at index #{index}: #{original} should be #{sorted}")
      nil ->
        IO.puts("  Data appears to be sorted")
    end

    false
  else
    true
  end
end
```

**Fix:**

```elixir
def sort_by_timestamp(data) do
  Enum.sort_by(data, fn {timestamp, _value} -> timestamp end)
end
```

### Duplicate Timestamps

**Problem:** Multiple values for the same timestamp

**Detection and handling:**

```elixir
def handle_duplicate_timestamps(data, strategy \\ :average) do
  grouped = Enum.group_by(data, fn {ts, _val} -> ts end)

  duplicates = Enum.filter(grouped, fn {_ts, values} -> length(values) > 1 end)

  if length(duplicates) > 0 do
    IO.puts("⚠️  Found #{length(duplicates)} duplicate timestamps")
  end

  Enum.map(grouped, fn {ts, values} ->
    case {strategy, values} do
      {_, [{ts, val}]} -> {ts, val}  # Single value, keep as-is

      {:average, values} ->
        avg_val = values |> Enum.map(fn {_, v} -> v end) |> Enum.sum() |> div(length(values))
        {ts, avg_val}

      {:first, [first | _]} -> first
      {:last, values} -> List.last(values)

      {:max, values} ->
        max_val = values |> Enum.map(fn {_, v} -> v end) |> Enum.max()
        {ts, max_val}
    end
  end)
  |> Enum.sort_by(fn {ts, _} -> ts end)
end
```

## Debugging Tools

### Compression Analysis Tool

```elixir
defmodule CompressionAnalyzer do
  def analyze(data) do
    # Basic statistics
    values = Enum.map(data, fn {_, v} -> v end)
    timestamps = Enum.map(data, fn {ts, _} -> ts end)

    stats = %{
      count: length(data),
      value_range: {Enum.min(values), Enum.max(values)},
      timestamp_range: {Enum.min(timestamps), Enum.max(timestamps)},
      unique_values: Enum.uniq(values) |> length(),
      avg_value: Enum.sum(values) / length(values)
    }

    # Compression test
    {compress_time, compression_result} = :timer.tc(fn ->
      GorillaStream.compress(data)
    end)

    compression_stats = case compression_result do
      {:ok, compressed} ->
        original_size = length(data) * 16
        compressed_size = byte_size(compressed)

        %{
          success: true,
          compress_time_us: compress_time,
          original_size: original_size,
          compressed_size: compressed_size,
          compression_ratio: compressed_size / original_size,
          compression_rate: length(data) / (compress_time / 1_000_000)
        }

      {:error, reason} ->
        %{success: false, error: reason}
    end

    Map.merge(stats, compression_stats)
  end

  def print_analysis(analysis) do
    IO.puts("\n=== Compression Analysis ===")
    IO.puts("Data points: #{analysis.count}")
    IO.puts("Value range: #{inspect(analysis.value_range)}")
    IO.puts("Unique values: #{analysis.unique_values} (#{Float.round(analysis.unique_values / analysis.count * 100, 1)}%)")

    if analysis.success do
      IO.puts("Compression ratio: #{Float.round(analysis.compression_ratio, 4)} (#{Float.round((1 - analysis.compression_ratio) * 100, 1)}% reduction)")
      IO.puts("Compression rate: #{Float.round(analysis.compression_rate, 0)} points/sec")
      IO.puts("Compression time: #{analysis.compress_time_us}μs")
    else
      IO.puts("❌ Compression failed: #{analysis.error}")
    end
  end
end
```

### Performance Profiler

```elixir
defmodule PerformanceProfiler do
  def profile_compression(data) do
    # CPU profiling
    :fprof.apply(&GorillaStream.compress/1, [data])
    :fprof.profile()
    :fprof.analyse()
  end

  def memory_profile(data) do
    # Memory profiling
    :erlang.trace(self(), true, [:garbage_collection])

    result = GorillaStream.compress(data)

    receive do
      {:trace, _pid, :gc_start, info} ->
        IO.puts("GC started: #{inspect(info)}")
    after 100 -> :ok
    end

    :erlang.trace(self(), false, [:garbage_collection])
    result
  end
end
```

## FAQ

### Q: Why is my compression ratio poor?

**A:** Poor compression (>80%) usually indicates:

- Random or highly variable data
- Unsorted timestamps
- No patterns in the data
- Inappropriate use case for Gorilla compression

Try the estimation function first:

```elixir
{:ok, ratio} = GorillaStream.Compression.Gorilla.Encoder.estimate_compression_ratio(data)
```

### Q: Should I use zlib compression?

**A:** Use zlib (`true` parameter) when:

- Storing data long-term (archival)
- Network bandwidth is limited
- Storage cost is a concern

Don't use zlib when:

- Real-time processing is required
- CPU usage is a concern
- Data will be decompressed frequently

### Q: How do I handle corrupted compressed data?

**A:** Always wrap decompression in error handling:

```elixir
def safe_decompress(compressed_data, use_zlib \\ false) do
  case GorillaStream.decompress(compressed_data, use_zlib) do
    {:ok, data} -> {:ok, data}
    {:error, _reason} ->
      Logger.error("Failed to decompress data, using fallback")
      {:ok, []}  # or load from backup
  end
end
```

### Q: What's the optimal batch size?

**A:** Depends on your data and system:

- **Small batches** (100-1K): Lower memory, higher overhead
- **Medium batches** (1K-10K): Good balance for most cases
- **Large batches** (10K+): Higher memory, better compression

Test with your actual data:

```elixir
def find_optimal_batch_size(sample_data) do
  [500, 1000, 2500, 5000, 10000]
  |> Enum.map(fn size ->
    data_subset = Enum.take(sample_data, size)
    {time, _} = :timer.tc(fn ->
      GorillaStream.compress(data_subset)
    end)
    rate = size / (time / 1_000_000)
    {size, rate}
  end)
  |> Enum.max_by(fn {_size, rate} -> rate end)
end
```

### Q: Can I compress data from multiple sensors together?

**A:** No, compress each sensor separately:

```elixir
# ❌ Don't mix sensors
mixed_data = sensor_1_data ++ sensor_2_data

# ✅ Compress separately
{:ok, sensor_1_compressed} = GorillaStream.compress(sensor_1_data)
{:ok, sensor_2_compressed} = GorillaStream.compress(sensor_2_data)
```

### Q: How do I migrate from other compression libraries?

**A:** Gradual migration approach:

```elixir
defmodule MigrationHelper do
  def compress_with_fallback(data) do
    case GorillaStream.compress(data) do
      {:ok, compressed} -> {:gorilla, compressed}
      {:error, _reason} -> {:legacy, OldCompression.compress(data)}
    end
  end

  def decompress_with_fallback({:gorilla, data}) do
    GorillaStream.decompress(data)
  end
  def decompress_with_fallback({:legacy, data}) do
    OldCompression.decompress(data)
  end
end
```

Need more help? Check the [User Guide](user_guide.md) and [Performance Guide](performance_guide.md) or open an issue on the project repository.
