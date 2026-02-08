# GorillaStream

[![CI](https://github.com/awksedgreep/gorilla_stream/actions/workflows/ci.yml/badge.svg)](https://github.com/awksedgreep/gorilla_stream/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/gorilla_stream.svg)](https://hex.pm/packages/gorilla_stream)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/gorilla_stream)

A high-performance, lossless compression library for time series data in Elixir, implementing Facebook's [Gorilla compression algorithm](http://www.vldb.org/pvldb/vol8/p1816-teller.pdf).

## Features

- **Lossless Compression**: Perfect reconstruction of original time series data
- **High Performance**: 4.3M points/sec average encoding throughput
- **Excellent Compression Ratios**: 2-42x compression depending on data patterns
- **Container Compression**: Optional zlib or zstd compression layer for additional size reduction
- **VictoriaMetrics Preprocessing**: Enabled by default to improve compression for gauges and counters
- **Streaming Support**: Real-time streaming and chunked processing for large datasets

## Installation

Add `gorilla_stream` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 1.3"}
  ]
end
```

For better compression ratios, optionally add zstd support:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 1.3"},
    {:ezstd, "~> 1.2"}  # Optional - enables zstd compression
  ]
end
```

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

# Compress the data
{:ok, compressed} = GorillaStream.compress(data)

# Decompress back to original
{:ok, decompressed} = GorillaStream.decompress(compressed)

# Verify lossless compression
decompressed == data  # => true
```

## Container Compression

GorillaStream supports optional container compression on top of Gorilla encoding:

| Option | Description |
|--------|-------------|
| `:none` | No container compression (default) |
| `:zlib` | Zlib compression (always available, built into Erlang) |
| `:zstd` | Zstd compression (requires `ezstd` package) |
| `:auto` | Use zstd if available, fall back to zlib |

```elixir
# Zlib compression (always available)
{:ok, compressed} = GorillaStream.compress(data, compression: :zlib)
{:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zlib)

# Zstd compression (best ratio, requires ezstd)
{:ok, compressed} = GorillaStream.compress(data, compression: :zstd)
{:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)

# Auto-select best available
{:ok, compressed} = GorillaStream.compress(data, compression: :auto)
{:ok, decompressed} = GorillaStream.decompress(compressed, compression: :auto)

# Check zstd availability at runtime
GorillaStream.zstd_available?()  # => true or false
```

## Streaming and Chunked Processing

Process large datasets efficiently using chunked streams:

```elixir
alias GorillaStream.Stream, as: GStream

large_dataset
|> GStream.compress_stream(chunk_size: 10_000)
|> Enum.to_list()
# => [{:ok, chunk1, metadata1}, {:ok, chunk2, metadata2}, ...]
```

See the [User Guide](https://hexdocs.pm/gorilla_stream/user_guide.html) for streaming, GenStage, Broadway, and Flow integration examples.

## Analysis Tools

GorillaStream includes Mix tasks to help evaluate compression strategies:

```bash
# Analyze compression ratios across data patterns
mix gorilla_stream.compression_analysis

# Benchmark VictoriaMetrics preprocessing
mix gorilla_stream.vm_benchmark 10000
```

## When to Use

**Ideal for:**
- Time series monitoring data (CPU, memory, temperature sensors)
- Financial tick data with gradual price changes
- IoT sensor readings with regular intervals
- System metrics with slowly changing values

**Not optimal for:**
- Completely random data with no patterns
- Text or binary data (use general-purpose compression)
- Data with frequent large jumps between values

## Documentation

- [User Guide](https://hexdocs.pm/gorilla_stream/user_guide.html) - Comprehensive usage examples and best practices
- [Performance Guide](https://hexdocs.pm/gorilla_stream/performance_guide.html) - Optimization strategies and benchmarks
- [Troubleshooting](https://hexdocs.pm/gorilla_stream/troubleshooting.html) - Common issues and solutions
- [API Reference](https://hexdocs.pm/gorilla_stream)

## License

MIT - see [LICENSE](LICENSE) for details.
