# Gorilla Stream Library - User Guide

## Table of Contents
1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [API Reference](#api-reference)
5. [Performance Guide](#performance-guide)
6. [Data Patterns & Compression](#data-patterns--compression)
7. [Error Handling](#error-handling)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)
10. [Examples](#examples)

## Introduction

The Gorilla Stream Library is a high-performance, lossless compression library specifically designed for time series data. It implements Facebook's Gorilla compression algorithm, which is optimized for time-stamped floating-point data commonly found in monitoring, IoT, and financial applications.

### Key Features

- **Lossless Compression**: Perfect reconstruction of original data
- **High Performance**: 1.7M+ points/sec encoding, up to 2M points/sec decoding
- **Excellent Compression Ratios**: 2-42x compression depending on data patterns
- **Production Ready**: Comprehensive error handling and validation
- **Memory Efficient**: ~117 bytes/point memory usage for large datasets

### When to Use Gorilla Compression

✅ **Ideal for:**
- Time series monitoring data (CPU, memory, temperature sensors)
- Financial tick data with gradual price changes  
- IoT sensor readings with regular intervals
- System metrics with slowly changing values

❌ **Not optimal for:**
- Completely random data with no patterns
- Text or binary data (use general-purpose compression)
- Data with frequent large jumps between values

## Installation

Add `gorilla_stream` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Quick Start

### Basic Compression and Decompression

```elixir
# Sample time series data: {timestamp, value} tuples
data = [
  {1609459200, 23.5},  # Temperature readings
  {1609459260, 23.7},  # Every minute
  {1609459320, 23.4},
  {1609459380, 23.6},
  {1609459440, 23.8}
]

# Compress the data
{:ok, compressed} = GorillaStream.Compression.Gorilla.compress(data, false)

# Decompress back to original
{:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, false)

# Verify lossless compression
decompressed == data  # => true
```

### With Optional Zlib Compression

```elixir
# Enable additional zlib compression for even better ratios
{:ok, compressed} = GorillaStream.Compression.Gorilla.compress(data, true)
{:ok, decompressed} = GorillaStream.Compression.Gorilla.decompress(compressed, true)
```

## API Reference

### Main Functions

#### `GorillaStream.Compression.Gorilla.compress/2`

Compresses time series data using the Gorilla algorithm.

**Parameters:**
- `data` - List of `{timestamp, value}` tuples where:
  - `timestamp` - Integer (Unix timestamp or sequence number)
  - `value` - Float (the measurement value)
- `use_zlib` - Boolean (whether to apply additional zlib compression)

**Returns:**
- `{:ok, compressed_binary}` - Success with compressed data
- `{:error, reason}` - Error with description

**Example:**
```elixir
data = [{1609459200, 42.5}, {1609459201, 42.7}]
{:ok, compressed} = GorillaStream.Compression.Gorilla.compress(data, false)
```

#### `GorillaStream.Compression.Gorilla.decompress/2`

Decompresses Gorilla-compressed data back to original format.

**Parameters:**
- `compressed_data` - Binary data from compress/2
- `use_zlib` - Boolean (must match the compress call)

**Returns:**
- `{:ok, decompressed_data}` - List of `{timestamp, value}` tuples
- `{:error, reason}` - Error with description

**Example:**
```elixir
{:ok, original_data} = GorillaStream.Compression.Gorilla.decompress(compressed, false)
```

### Encoder Module Functions

#### `GorillaStream.Compression.Gorilla.Encoder.encode/1`

Low-level encoding function for advanced use cases.

```elixir
{:ok, encoded} = GorillaStream.Compression.Gorilla.Encoder.encode(data)
```

#### `GorillaStream.Compression.Gorilla.Encoder.estimate_compression_ratio/1`

Estimates compression ratio without actually compressing.

```elixir
{:ok, ratio} = GorillaStream.Compression.Gorilla.Encoder.estimate_compression_ratio(data)
# ratio: 0.0 to 1.0 (lower is better compression)
```

### Decoder Module Functions

#### `GorillaStream.Compression.Gorilla.Decoder.decode/1`

Low-level decoding function.

```elixir
{:ok, decoded} = GorillaStream.Compression.Gorilla.Decoder.decode(encoded_data)
```

## Performance Guide

### Compression Performance by Data Pattern

| Data Pattern | Compression Ratio | Encoding Speed | Decoding Speed |
|--------------|-------------------|----------------|----------------|
| Identical values | 42x (2.4%) | 10M+ points/sec | 600K points/sec |
| Gradual changes | 1.9x (53%) | 1.8M points/sec | 500K points/sec |
| Step functions | 39x (2.6%) | 10M+ points/sec | 600K points/sec |
| Random walk | 1.9x (53%) | 1.8M points/sec | 500K points/sec |

### Performance Optimization Tips

1. **Batch Size**: Process 1,000-10,000 points per batch for optimal performance
2. **Memory**: Expect ~117 bytes/point memory usage during processing
3. **Concurrent Processing**: Library is thread-safe for concurrent operations
4. **Data Ordering**: Keep timestamps in ascending order for best performance

### Benchmark Results

Tested on typical hardware with 5,000 sensor data points:

```
Gorilla Compression:
  - Size: 41,996 bytes (52.5% of original)
  - Encode: 2.8ms
  - Decode: 51ms

Comparison with alternatives:
  - Raw Binary: 80,007 bytes (100% - no compression)
  - Zlib: 53,475 bytes (66.8% of original)
```

### Memory Usage Guidelines

- **Small datasets** (< 1K points): < 1MB memory usage
- **Medium datasets** (1K-10K points): 1-10MB memory usage  
- **Large datasets** (10K-100K points): 10-50MB memory usage
- **Very large datasets** (100K+ points): Scale linearly

## Data Patterns & Compression

### Excellent Compression (90%+ reduction)

**Identical Values:**
```elixir
# Temperature sensor with stable reading
data = [
  {1609459200, 23.5},
  {1609459260, 23.5},  # Same value
  {1609459320, 23.5},  # Same value
  {1609459380, 23.5}   # Same value
]
# Expected: 95%+ compression
```

**Step Functions:**
```elixir
# System states or discrete levels
data = [
  {1609459200, 100.0},  # State 1
  {1609459260, 100.0},
  {1609459320, 100.0},
  {1609459380, 200.0},  # State 2
  {1609459440, 200.0},
  {1609459500, 200.0}
]
# Expected: 90%+ compression
```

### Good Compression (40-70% reduction)

**Gradual Changes:**
```elixir
# Temperature rising slowly
data = [
  {1609459200, 20.0},
  {1609459260, 20.1},
  {1609459320, 20.2},
  {1609459380, 20.3}
]
# Expected: 40-50% compression
```

**Seasonal Patterns:**
```elixir
# Daily temperature cycle
data = for i <- 0..1440 do  # 24 hours, every minute
  temp = 20.0 + 5.0 * :math.sin(i * 2 * :math.pi / 1440)
  {1609459200 + i * 60, temp}
end
# Expected: 40-60% compression
```

### Poor Compression (< 30% reduction)

**Random Data:**
```elixir
# Completely random values
data = for i <- 0..100 do
  {1609459200 + i, :rand.uniform() * 1000}
end
# Expected: 10-20% compression
```

## Error Handling

### Common Error Scenarios

#### Invalid Input Data

```elixir
# Wrong data format
{:error, "Invalid input data"} = 
  GorillaStream.Compression.Gorilla.compress("not_a_list", false)

# Invalid tuple structure  
{:error, "Invalid data format: expected {timestamp, float} tuple"} =
  GorillaStream.Compression.Gorilla.compress([{1, 2, 3}], false)

# Non-numeric values
{:error, "Invalid data format: expected {timestamp, float} tuple"} =
  GorillaStream.Compression.Gorilla.compress([{1, "invalid"}], false)
```

#### Compression Errors

```elixir
# Handle encoding errors gracefully
case GorillaStream.Compression.Gorilla.compress(data, false) do
  {:ok, compressed} -> 
    # Process compressed data
    IO.puts("Compressed #{length(data)} points")
    
  {:error, reason} -> 
    # Log error and handle gracefully
    Logger.error("Compression failed: #{reason}")
    {:error, :compression_failed}
end
```

#### Decompression Errors

```elixir
# Handle corrupted or invalid compressed data
case GorillaStream.Compression.Gorilla.decompress(compressed_data, false) do
  {:ok, decompressed} ->
    {:ok, decompressed}
    
  {:error, reason} ->
    Logger.warning("Decompression failed: #{reason}")
    # Return empty data or retry with backup
    {:ok, []}
end
```

## Best Practices

### Data Preparation

1. **Sort by Timestamp**: Ensure data is sorted by timestamp for optimal compression
```elixir
data = Enum.sort_by(unsorted_data, fn {timestamp, _value} -> timestamp end)
```

2. **Validate Data Types**: Ensure consistent data types
```elixir
def validate_data_point({timestamp, value}) when is_integer(timestamp) and is_number(value) do
  {timestamp, value * 1.0}  # Convert to float
end
```

3. **Handle Missing Values**: Decide on strategy for gaps in data
```elixir
# Option 1: Interpolate missing values
# Option 2: Use special sentinel values
# Option 3: Split into separate compression blocks
```

### Production Usage

1. **Error Handling**: Always wrap compression calls in error handling
```elixir
def safe_compress(data) do
  case GorillaStream.Compression.Gorilla.compress(data, false) do
    {:ok, compressed} -> {:ok, compressed}
    {:error, _reason} = error -> error
  end
end
```

2. **Monitoring**: Track compression ratios and performance
```elixir
def compress_with_metrics(data) do
  original_size = length(data) * 16  # 8 bytes timestamp + 8 bytes float
  
  case GorillaStream.Compression.Gorilla.compress(data, false) do
    {:ok, compressed} -> 
      ratio = byte_size(compressed) / original_size
      :telemetry.execute(:gorilla_compression, %{ratio: ratio, points: length(data)})
      {:ok, compressed}
      
    error -> error
  end
end
```

3. **Batch Processing**: Process data in optimal batch sizes
```elixir
def compress_large_dataset(data) do
  data
  |> Enum.chunk_every(5000)  # Optimal batch size
  |> Enum.map(&safe_compress/1)
  |> handle_batch_results()
end
```

### Memory Management

1. **Stream Processing**: For very large datasets, consider streaming
```elixir
def compress_stream(data_stream) do
  data_stream
  |> Stream.chunk_every(1000)
  |> Stream.map(&GorillaStream.Compression.Gorilla.compress(&1, false))
  |> Enum.to_list()
end
```

2. **Garbage Collection**: Force GC for long-running processes
```elixir
def compress_with_gc(data) do
  result = GorillaStream.Compression.Gorilla.compress(data, false)
  :erlang.garbage_collect()  # Clean up after large compression
  result
end
```

## Troubleshooting

### Performance Issues

**Problem**: Slow compression/decompression
**Solutions:**
- Reduce batch size to 1,000-5,000 points
- Check for memory pressure
- Verify data is properly sorted by timestamp
- Consider using multiple processes for very large datasets

**Problem**: Poor compression ratios
**Solutions:**
- Analyze your data patterns (use `estimate_compression_ratio/1`)
- Ensure timestamps are in ascending order
- Check for outliers or noise in the data
- Consider preprocessing to remove noise

### Memory Issues

**Problem**: High memory usage
**Solutions:**
- Process data in smaller batches
- Use streaming for very large datasets
- Force garbage collection between batches
- Monitor memory usage with `:erlang.memory()`

### Data Quality Issues

**Problem**: Compression fails with format errors
**Solutions:**
- Validate all data points before compression
- Ensure timestamps are integers and values are numbers
- Check for NaN or infinity values
- Verify tuple structure: `{timestamp, value}`

### Common Error Messages

| Error Message | Cause | Solution |
|---------------|--------|----------|
| "Invalid input data" | Non-list input | Pass a list of tuples |
| "Invalid data format" | Wrong tuple structure | Use `{timestamp, value}` format |
| "expected {timestamp, float} tuple" | Wrong data types | Ensure integer timestamps, numeric values |
| "Insufficient data for initial values" | Corrupted compressed data | Check data integrity |

## Examples

### Real-World Use Cases

#### 1. Temperature Monitoring System

```elixir
defmodule TemperatureMonitor do
  alias GorillaStream.Compression.Gorilla
  
  def compress_hourly_readings(sensor_id, readings) do
    # Convert to required format
    data = Enum.map(readings, fn reading ->
      {reading.timestamp, reading.temperature}
    end)
    
    case Gorilla.compress(data, true) do  # Use zlib for better compression
      {:ok, compressed} ->
        # Store compressed data with metadata
        %{
          sensor_id: sensor_id,
          compressed_data: compressed,
          original_count: length(data),
          compressed_size: byte_size(compressed),
          compression_ratio: byte_size(compressed) / (length(data) * 16)
        }
        
      {:error, reason} ->
        Logger.error("Failed to compress readings for sensor #{sensor_id}: #{reason}")
        {:error, reason}
    end
  end
  
  def decompress_readings(compressed_record) do
    case Gorilla.decompress(compressed_record.compressed_data, true) do
      {:ok, data} ->
        # Convert back to structs
        readings = Enum.map(data, fn {timestamp, temperature} ->
          %Reading{timestamp: timestamp, temperature: temperature}
        end)
        {:ok, readings}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

#### 2. Financial Tick Data Processing

```elixir
defmodule TickDataProcessor do
  alias GorillaStream.Compression.Gorilla
  
  def compress_price_data(symbol, ticks) do
    # Process price data
    price_data = Enum.map(ticks, fn tick ->
      {tick.timestamp, tick.price}
    end)
    
    # Process volume data separately (different compression characteristics)
    volume_data = Enum.map(ticks, fn tick ->
      {tick.timestamp, tick.volume}
    end)
    
    with {:ok, compressed_prices} <- Gorilla.compress(price_data, false),
         {:ok, compressed_volumes} <- Gorilla.compress(volume_data, false) do
      
      {:ok, %{
        symbol: symbol,
        price_data: compressed_prices,
        volume_data: compressed_volumes,
        tick_count: length(ticks)
      }}
    else
      error -> error
    end
  end
  
  def analyze_compression_efficiency(ticks) do
    price_data = Enum.map(ticks, fn tick -> {tick.timestamp, tick.price} end)
    
    {:ok, ratio} = Gorilla.estimate_compression_ratio(price_data)
    
    cond do
      ratio < 0.3 -> :excellent_compression
      ratio < 0.6 -> :good_compression  
      ratio < 0.8 -> :moderate_compression
      true -> :poor_compression
    end
  end
end
```

#### 3. IoT Sensor Data Pipeline

```elixir
defmodule IoTDataPipeline do
  alias GorillaStream.Compression.Gorilla
  
  def process_sensor_batch(sensors_data) do
    # Process multiple sensors concurrently
    sensors_data
    |> Task.async_stream(fn {sensor_id, readings} ->
      compress_sensor_data(sensor_id, readings)
    end, max_concurrency: 10)
    |> Enum.map(fn {:ok, result} -> result end)
  end
  
  defp compress_sensor_data(sensor_id, readings) do
    # Convert readings to time series format
    data = Enum.map(readings, fn reading ->
      {reading.timestamp, reading.value}
    end)
    
    # Estimate compression first
    {:ok, estimated_ratio} = Gorilla.estimate_compression_ratio(data)
    
    # Only compress if we expect good compression
    if estimated_ratio < 0.8 do
      case Gorilla.compress(data, false) do
        {:ok, compressed} ->
          {:ok, %{
            sensor_id: sensor_id,
            data: compressed,
            original_points: length(data),
            estimated_ratio: estimated_ratio,
            actual_ratio: byte_size(compressed) / (length(data) * 16)
          }}
          
        error -> error
      end
    else
      # Store uncompressed for poor compression candidates
      {:ok, %{
        sensor_id: sensor_id,
        data: :erlang.term_to_binary(data),
        original_points: length(data),
        compressed: false
      }}
    end
  end
end
```

#### 4. System Metrics Archival

```elixir
defmodule MetricsArchival do
  alias GorillaStream.Compression.Gorilla
  
  def archive_daily_metrics(date, metrics) do
    # Group metrics by type for better compression  
    grouped_metrics = Enum.group_by(metrics, & &1.metric_type)
    
    compressed_metrics = 
      for {metric_type, metric_list} <- grouped_metrics do
        data = Enum.map(metric_list, fn m -> {m.timestamp, m.value} end)
        
        {:ok, compressed} = Gorilla.compress(data, true)  # Use zlib for archival
        
        {metric_type, %{
          compressed_data: compressed,
          point_count: length(data),
          compression_ratio: byte_size(compressed) / (length(data) * 16)
        }}
      end
    
    # Store archive record  
    %{
      date: date,
      metrics: Map.new(compressed_metrics),
      total_points: length(metrics),
      archived_at: DateTime.utc_now()
    }
  end
  
  def retrieve_metrics(archive_record, metric_types) do
    retrieved_metrics = 
      for metric_type <- metric_types,
          archived_metric = archive_record.metrics[metric_type] do
        
        {:ok, data} = Gorilla.decompress(archived_metric.compressed_data, true)
        
        metrics = Enum.map(data, fn {timestamp, value} ->
          %Metric{
            timestamp: timestamp,
            metric_type: metric_type,
            value: value
          }
        end)
        
        {metric_type, metrics}
      end
    
    Map.new(retrieved_metrics)
  end
end
```

### Integration Patterns

#### GenServer Integration

```elixir
defmodule CompressionWorker do
  use GenServer
  alias GorillaStream.Compression.Gorilla
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def compress_async(data) do
    GenServer.cast(__MODULE__, {:compress, data, self()})
  end
  
  def init(_opts) do
    {:ok, %{}}
  end
  
  def handle_cast({:compress, data, caller}, state) do
    # Perform compression in background
    Task.start(fn ->
      result = Gorilla.compress(data, false)
      send(caller, {:compression_result, result})
    end)
    
    {:noreply, state}
  end
end
```

#### Phoenix LiveView Integration

```elixir
defmodule MyAppWeb.MetricsLive do
  use MyAppWeb, :live_view
  alias GorillaStream.Compression.Gorilla
  
  def handle_event("compress_data", %{"data" => raw_data}, socket) do
    parsed_data = Jason.decode!(raw_data)
    data = Enum.map(parsed_data, fn [ts, val] -> {ts, val} end)
    
    case Gorilla.compress(data, false) do
      {:ok, compressed} ->
        compression_ratio = byte_size(compressed) / (length(data) * 16)
        
        socket = 
          socket
          |> assign(:compressed_data, compressed)
          |> assign(:compression_ratio, compression_ratio)
          |> put_flash(:info, "Data compressed successfully!")
        
        {:noreply, socket}
        
      {:error, reason} ->
        socket = put_flash(socket, :error, "Compression failed: #{reason}")
        {:noreply, socket}
    end
  end
end
```

## Conclusion

The Gorilla Stream Library provides a robust, high-performance solution for time series data compression. With proper usage following the guidelines in this document, you can achieve excellent compression ratios while maintaining perfect data fidelity.

For additional support or questions, please refer to the project repository or open an issue with specific details about your use case.