````markdown
# GorillaStream

A high-performance, lossless compression library for time series data in Elixir, implementing Facebook's Gorilla compression algorithm.

## Features

- **Lossless Compression**: Perfect reconstruction of original time series data
- **High Performance**: 1.7M+ points/sec encoding, up to 2M points/sec decoding
- **Excellent Compression Ratios**: 2-42x compression depending on data patterns
- **Production Ready**: Comprehensive error handling and validation
- **Memory Efficient**: ~117 bytes/point memory usage for large datasets
- **Zlib Support**: Optional additional compression layer

## Quick Start

```elixir
# Sample time series data: {timestamp, value} tuples
data = [
  {1609459200, 23.5},
  {1609459260, 23.7},
  {1609459320, 23.4},
  {1609459380, 23.6},
  {1609459440, 23.8}
]

# Compress the data (simple API)
{:ok, compressed} = GorillaStream.compress(data)

# Decompress back to original
{:ok, decompressed} = GorillaStream.decompress(compressed)

# Verify lossless compression
decompressed == data  # => true

# With optional zlib compression for better ratios
{:ok, compressed} = GorillaStream.compress(data, true)
{:ok, decompressed} = GorillaStream.decompress(compressed, true)
```

## Streaming and Chunking Examples

GorillaStream supports both **real-time streaming** (individual points) and **chunked processing** (large datasets).

### Real-time Streaming (Individual Points)

```elixir
# Stream real-time sensor data as it arrives
defmodule SensorStreaming do
  def start_sensor_stream(sensor_id) do
    # Simulate real-time sensor data stream
    Stream.unfold(DateTime.utc_now(), &next_sensor_reading/1)
    |> Stream.map(&compress_point/1)
    |> Stream.each(&store_compressed_point/1)
    |> Stream.run()
  end

  defp compress_point(data_point) do
    # Compress single point as it streams in
    case GorillaStream.compress([data_point]) do
      {:ok, compressed} ->
        {data_point, compressed, byte_size(compressed)}
      {:error, reason} ->
        {:error, data_point, reason}
    end
  end
end
```

### Chunked Processing (Large Datasets)

```elixir
# Process large datasets efficiently using chunks
alias GorillaStream.Stream, as: GStream

# Generate or read your large dataset as a stream
large_dataset = Stream.unfold(1609459200, fn timestamp ->
  if timestamp < 1609545600 do  # 24 hours of data
    point = {timestamp, 20.0 + :rand.normal() * 2}
    {point, timestamp + 60}  # Every minute
  else
    nil
  end
end)

# Compress in chunks of 10,000 points for efficiency
compressed_chunks =
  large_dataset
  |> GStream.compress_stream(chunk_size: 10_000)
  |> Enum.to_list()

# Each chunk is compressed independently with metadata
[{:ok, chunk1, metadata1}, {:ok, chunk2, metadata2} | _] = compressed_chunks

# Access metadata for each chunk
IO.inspect(metadata1)
# %{
#   original_points: 10000,
#   compressed_size: 52341,
#   timestamp_range: {1609459200, 1609459260}
# }
```

### Memory-Efficient Large File Processing

```elixir
# Process huge files without loading everything into memory
defmodule LargeFileProcessor do
  alias GorillaStream.{Stream, File}

  def process_csv_file(file_path) do
    file_path
    |> File.stream!([:read_ahead])
    |> Stream.drop(1)  # Skip header
    |> Stream.map(&parse_csv_line/1)
    |> Stream.chunk_every(50_000)  # Process in 50K chunks
    |> Stream.with_index()
    |> Stream.map(fn {chunk, index} ->
      # Compress each chunk and save to separate files
      {:ok, compressed} = GorillaStream.compress(chunk)
      filename = "compressed_chunk_#{index}.gorilla"
      File.write!(filename, compressed)
      {filename, length(chunk), byte_size(compressed)}
    end)
    |> Enum.to_list()
  end

  # Later, decompress chunks back
  def load_compressed_chunks(chunk_files) do
    chunk_files
    |> Stream.map(fn filename ->
      compressed = File.read!(filename)
      {:ok, data} = GorillaStream.decompress(compressed)
      data
    end)
    |> Stream.concat()  # Flatten all chunks back into one stream
  end
end
```

### Adaptive Processing (Both Streaming and Chunking)

```elixir
# Automatically choose between streaming and chunking based on data rate
defmodule AdaptiveProcessor do
  def start_adaptive_processing(data_source) do
    data_source
    |> Stream.chunk_while(
      %{buffer: [], last_time: System.monotonic_time(:millisecond)},
      &chunk_or_stream/2,
      &finalize_buffer/1
    )
    |> Stream.map(&process_adaptively/1)
    |> Stream.run()
  end

  defp chunk_or_stream(point, %{buffer: buffer, last_time: last_time} = acc) do
    current_time = System.monotonic_time(:millisecond)
    time_diff = current_time - last_time
    new_buffer = [point | buffer]

    cond do
      # High data rate: use chunking for efficiency
      length(new_buffer) >= 1000 ->
        {:cont, Enum.reverse(new_buffer), %{buffer: [], last_time: current_time}}

      # Low data rate: stream individual points for low latency
      time_diff > 5000 and length(new_buffer) > 0 ->
        {:cont, Enum.reverse(new_buffer), %{buffer: [], last_time: current_time}}

      # Keep buffering
      true ->
        {:cont, %{buffer: new_buffer, last_time: last_time}}
    end
  end

  defp finalize_buffer(%{buffer: []}), do: {:cont, []}
  defp finalize_buffer(%{buffer: buffer}), do: {:cont, Enum.reverse(buffer), %{buffer: []}}

  defp process_adaptively(data_points) when length(data_points) == 1 do
    # Single point - streaming compression
    [point] = data_points
    case GorillaStream.compress([point]) do
      {:ok, compressed} ->
        IO.puts("Streamed single point: #{byte_size(compressed)} bytes")
      {:error, reason} ->
        Logger.error("Streaming failed: #{reason}")
    end
  end

  defp process_adaptively(data_points) when length(data_points) > 1 do
    # Multiple points - chunk compression
    case GorillaStream.compress(data_points) do
      {:ok, compressed} ->
        IO.puts("Chunked #{length(data_points)} points: #{byte_size(compressed)} bytes")
      {:error, reason} ->
        Logger.error("Chunking failed: #{reason}")
    end
  end
end
```

### Real-time IoT Data Pipeline

```elixir
# Stream data from IoT devices with real-time compression
defmodule IoTDataPipeline do
  use GenServer

  def start_link(device_configs) do
    GenServer.start_link(__MODULE__, device_configs, name: __MODULE__)
  end

  def init(device_configs) do
    # Start streaming from multiple IoT devices
    devices = Enum.map(device_configs, &connect_device/1)
    {:ok, %{devices: devices, compression_stats: %{}}}
  end

  def handle_info({:device_data, device_id, {timestamp, value}}, state) do
    # Compress individual data points as they arrive from devices
    point = {timestamp, value}

    case GorillaStream.compress([point]) do
      {:ok, compressed} ->
        # Send compressed data to cloud/storage immediately
        CloudStorage.store_compressed(device_id, compressed)

        # Update compression stats
        stats = Map.get(state.compression_stats, device_id, %{points: 0, bytes: 0})
        new_stats = %{
          points: stats.points + 1,
          bytes: stats.bytes + byte_size(compressed)
        }

        new_state = put_in(state.compression_stats[device_id], new_stats)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("IoT compression failed for #{device_id}: #{reason}")
        {:noreply, state}
    end
  end

  defp connect_device({device_id, config}) do
    # Connect to device and start receiving data
    {:ok, pid} = IoTDevice.connect(device_id, config)
    IoTDevice.subscribe_data(pid, self())
    {device_id, pid}
  end
end
```

### GenStage Streaming Pipeline

```elixir
# Use GenStage for backpressure-aware streaming compression
defmodule StreamingProducer do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:producer, %{counter: 0}}
  end

  def handle_demand(demand, %{counter: counter} = state) when demand > 0 do
    # Generate streaming data points on demand
    events = for i <- counter..(counter + demand - 1) do
      timestamp = System.system_time(:second) + i
      value = :rand.normal() * 10 + 50  # Simulated sensor value
      {timestamp, value}
    end

    {:noreply, events, %{state | counter: counter + demand}}
  end
end

defmodule StreamingCompressor do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:producer_consumer, %{}, subscribe_to: [StreamingProducer]}
  end

  def handle_events(events, _from, state) do
    # Compress each streaming data point as it flows through
    compressed_events = Enum.map(events, fn point ->
      case GorillaStream.compress([point]) do
        {:ok, compressed} ->
          %{
            original: point,
            compressed: compressed,
            compression_ratio: byte_size(compressed) / 16,
            timestamp: System.system_time(:millisecond)
          }

        {:error, reason} ->
          %{error: reason, original: point}
      end
    end)

    {:noreply, compressed_events, state}
  end
end

defmodule StreamingConsumer do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:consumer, %{}, subscribe_to: [StreamingCompressor]}
  end

  def handle_events(events, _from, state) do
    # Process compressed streaming data
    Enum.each(events, fn
      %{compressed: compressed, original: {ts, val}} ->
        IO.puts("Streamed point #{ts}:#{val} -> #{byte_size(compressed)} bytes")

      %{error: reason} ->
        Logger.error("Streaming compression error: #{inspect(reason)}")
    end)

    {:noreply, [], state}
  end
end

# Start the streaming pipeline
def start_streaming_pipeline() do
  {:ok, _} = StreamingProducer.start_link([])
  {:ok, _} = StreamingCompressor.start_link([])
  {:ok, _} = StreamingConsumer.start_link([])
end
```

### Broadway Streaming Processing

```elixir
# Use Broadway for scalable streaming data processing
defmodule StreamingBroadway do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "sensor_data"},
        stages: 2
      ],
      processors: [
        default: [stages: 4]
      ],
      batchers: [
        compressed: [stages: 2, batch_size: 1]  # Process individually, not in batches
      ]
    )
  end

  def handle_message(:default, message, _context) do
    # Parse incoming streaming data
    {timestamp, value} = Jason.decode!(message.data)
    point = {timestamp, value}

    # Compress streaming data point
    case GorillaStream.compress([point]) do
      {:ok, compressed} ->
        # Add compression info to message
        message
        |> Message.put_data(%{
          original: point,
          compressed: compressed,
          compression_ratio: byte_size(compressed) / 16
        })
        |> Message.put_batcher(:compressed)

      {:error, reason} ->
        Message.failed(message, reason)
    end
  end

  def handle_batch(:compressed, messages, _batch_info, _context) do
    # Store compressed streaming data
    Enum.each(messages, fn message ->
      %{compressed: compressed, original: {ts, val}} = message.data
      StreamingStorage.store(ts, compressed)
      IO.puts("Processed streaming point: #{ts}:#{val}")
    end)

    messages
  end
end
```

### Flow-based Streaming

```elixir
# Use Flow for concurrent streaming data processing
defmodule FlowStreaming do
  def process_sensor_stream(data_source) do
    data_source
    |> Flow.from_enumerable()
    |> Flow.map(&parse_sensor_data/1)
    |> Flow.map(&compress_streaming_point/1)
    |> Flow.map(&store_compressed_point/1)
    |> Flow.run()
  end

  defp compress_streaming_point({timestamp, value} = point) do
    case GorillaStream.compress([point]) do
      {:ok, compressed} ->
        %{
          timestamp: timestamp,
          original_value: value,
          compressed_data: compressed,
          compressed_size: byte_size(compressed),
          processed_at: System.system_time(:millisecond)
        }

      {:error, reason} ->
        %{error: reason, point: point}
    end
  end

  defp store_compressed_point(%{compressed_data: compressed, timestamp: ts}) do
    Database.insert_compressed_point(ts, compressed)
    :ok
  end

  defp store_compressed_point(%{error: reason, point: point}) do
    Logger.error("Failed to compress streaming point #{inspect(point)}: #{reason}")
    :error
  end
end
```

### IoT Device Streaming

```elixir
# Stream data directly from IoT devices with real-time compression
defmodule IoTStreaming do
  use GenServer

  def start_link(device_id) do
    GenServer.start_link(__MODULE__, device_id, name: {:global, device_id})
  end

  def init(device_id) do
    # Connect to device and start streaming
    {:ok, socket} = connect_to_device(device_id)
    {:ok, %{device_id: device_id, socket: socket, buffer: []}}
  end

  def handle_info({:tcp, _socket, data}, state) do
    # Parse incoming streaming data from device
    case parse_device_data(data) do
      {:ok, {timestamp, sensor_values}} ->
        # Create data points for each sensor
        points = Enum.map(sensor_values, fn {sensor, value} ->
          {timestamp, value}
        end)

        # Compress streaming data immediately
        compressed_points = Enum.map(points, fn point ->
          case GorillaStream.compress([point]) do
            {:ok, compressed} ->
              # Send to cloud/storage immediately
              send_to_cloud(state.device_id, point, compressed)
              {point, compressed, :ok}

            {:error, reason} ->
              Logger.error("IoT streaming compression failed: #{reason}")
              {point, nil, :error}
          end
        end)

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to parse IoT data: #{reason}")
        {:noreply, state}
    end
  end

  defp send_to_cloud(device_id, {timestamp, value}, compressed_data) do
    CloudAPI.send_compressed_point(%{
      device_id: device_id,
      timestamp: timestamp,
      original_value: value,
      compressed_data: Base.encode64(compressed_data),
      compression_size: byte_size(compressed_data)
    })
  end
end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `gorilla_stream` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 1.1"}
  ]
end
```

## Documentation

See the [User Guide](docs/user_guide.md) for comprehensive usage examples and best practices.

Additional documentation:

- [Performance Guide](docs/performance_guide.md) - Optimization strategies and benchmarks
- [Troubleshooting Guide](docs/troubleshooting.md) - Common issues and solutions

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/gorilla_stream>.

## Analysis Tools

### Compression Analysis

To help determine when to use zlib compression alongside Gorilla compression, GorillaStream includes an analysis tool that tests different data patterns and provides recommendations:

```bash
mix gorilla_stream.compression_analysis
```

This tool will:
- Test various data patterns (stable sensors, noisy data, mixed patterns, etc.)
- Compare Gorilla-only vs Gorilla+zlib compression ratios
- Measure time overhead for additional compression
- Provide specific recommendations based on your use case

Sample output:
```
🎯 WHEN TO USE ZLIB WITH GORILLA COMPRESSION
============================================================

--- 1K Stable Sensor Data (1000 points) ---
Original size: 15.6KB
Gorilla only:  8.3KB (0.531) - 0ms
Combined:      7.3KB (0.467) - 0ms
📊 Additional compression: 12.0%
⚡ Time overhead: 50.1%
🎯 Recommendation: ✅ YES - Good benefit, reasonable overhead
```

The tool provides decision guidelines to help you choose the optimal compression strategy for your specific data patterns and performance requirements.

## When to Use

✅ **Ideal for:**

- Time series monitoring data (CPU, memory, temperature sensors)
- Financial tick data with gradual price changes
- IoT sensor readings with regular intervals
- System metrics with slowly changing values

❌ **Not optimal for:**

- Completely random data with no patterns
- Text or binary data (use general-purpose compression)
- Data with frequent large jumps between values
````
