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
