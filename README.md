# GorillaStream

[![CI](https://github.com/awksedgreep/gorilla_stream/actions/workflows/ci.yml/badge.svg)](https://github.com/awksedgreep/gorilla_stream/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/gorilla_stream.svg)](https://hex.pm/packages/gorilla_stream)
[![Docs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/gorilla_stream)

A high-performance, lossless compression library for time series data in Elixir, implementing Facebook's [Gorilla](http://www.vldb.org/pvldb/vol8/p1816-teller.pdf) and the [Chimp](https://www.vldb.org/pvldb/vol15/p3058-liakos.pdf) (VLDB 2022) compression algorithms.

## Features

- **Three Algorithms**: Gorilla, Chimp, and Chimp128 — all lossless, all streaming
- **High Performance**: 4.3M points/sec average encoding throughput
- **Excellent Compression Ratios**: 2-42x compression depending on data patterns
- **Container Compression**: Optional zlib or zstd compression layer for additional size reduction
- **VictoriaMetrics Preprocessing**: Enabled by default to improve compression for gauges and counters
- **Streaming Support**: All algorithms encode/decode point-by-point with no lookahead required

## Installation

Add `gorilla_stream` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 3.0"}
  ]
end
```

For better compression ratios, optionally add zstd support:

```elixir
def deps do
  [
    {:gorilla_stream, "~> 3.0"},
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

# Compress with Gorilla (default)
{:ok, compressed} = GorillaStream.compress(data)

# Compress with Chimp
{:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp)

# Compress with Chimp128 (ring buffer of 128 previous values)
{:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128)

# Decompress — auto-detects algorithm
{:ok, decompressed} = GorillaStream.decompress(compressed)

# Verify lossless compression
decompressed == data  # => true
```

## Algorithms

### Gorilla (default)

Facebook's original algorithm (VLDB 2015). XOR-based encoding with 3-case variable-length
flags. Best general-purpose choice.

### Chimp

Improved XOR encoding (VLDB 2022) with:
- Uniform 2-bit flags (4 cases) instead of Gorilla's variable 1/2/2 bits
- 3-bit leading zero buckets instead of 5-bit raw count
- Trailing zero stripping when > 6 trailing zeros

Modest improvement over Gorilla (~2 bits per value saved).

### Chimp128

Chimp with a **ring buffer of 128 previous values**. For each new value, it selects
the reference value (from the last 128) that produces the most trailing zeros in the
XOR result. This benefits data with repeating patterns or values that revisit previous
states.

All three algorithms are fully streaming — encode/decode one point at a time with no
lookahead or chunking required. Timestamps use the same delta-of-delta encoding across
all algorithms.

```elixir
# Algorithm selection
{:ok, _} = GorillaStream.compress(data)                        # Gorilla
{:ok, _} = GorillaStream.compress(data, algorithm: :chimp)     # Chimp
{:ok, _} = GorillaStream.compress(data, algorithm: :chimp128)  # Chimp128

# Decompress auto-detects — no algorithm option needed
{:ok, _} = GorillaStream.decompress(compressed)
```

## Container Compression

GorillaStream supports optional container compression on top of the value encoding:

| Option | Description |
|--------|-------------|
| `:none` | No container compression (default) |
| `:zlib` | Zlib compression (always available, built into Erlang) |
| `:zstd` | Zstd compression (requires `ezstd` package) |
| `:auto` | Use zstd if available, fall back to zlib |

```elixir
# Zstd compression (best ratio, requires ezstd)
{:ok, compressed} = GorillaStream.compress(data, compression: :zstd)
{:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)

# Combine algorithm + container
{:ok, compressed} = GorillaStream.compress(data, algorithm: :chimp128, compression: :zstd)
{:ok, decompressed} = GorillaStream.decompress(compressed, compression: :zstd)

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
