# Feature Request: Add VictoriaMetrics-Style Compression Option

## Summary
Add a `victoria_metrics: boolean` flag to the existing `compress/2` function to enable VictoriaMetrics-style compression enhancements on top of the current Gorilla compression (delta-of-delta timestamps, XOR-based float compression, optional zlib). The goal is to improve compression ratios (potentially 2-10x better, per VictoriaMetrics benchmarks) for time-series data while minimizing external dependencies.

## Proposed Implementation

### Overview
The feature will extend the existing compression pipeline by adding optional preprocessing steps (float-to-integer scaling, delta encoding for counters) and supporting Zstandard (Zstd) as an alternative to zlib, with fallback to the existing zlib implementation. All enhancements will be lossless, matching Gorilla’s guarantees.

### Details
1. **Float-to-Integer Conversion**:
   - Before XOR compression, scale float values by \(10^N\), where \(N\) is the maximum number of decimal places in the series (e.g., `[1.23, 4.56]` → `[123, 456]` with \(N=2\)).
   - Store \(N\) as metadata for lossless reversal.
   - Use standard library (`Kernel.trunc/1`, `Enum`, `Integer.pow/2` or custom `pow/2`).
   - Example:
     ```elixir
     def scale_floats_to_ints(values) do
       max_decimals = 2  # TODO: Scan values to determine
       scale = Integer.pow(10, max_decimals)
       scaled = Enum.map(values, &trunc(&1 * scale))
       {scaled, max_decimals}
     end
     ```

2. **Delta Encoding for Counters**:
   - For monotonic series (e.g., `[100, 110, 125]`), store the initial value and differences (`[100, 10, 15]`) before scaling/XOR.
   - Add an optional `is_counter: boolean` flag or heuristic (e.g., check non-negative deltas).
   - Use standard library (`Enum.reduce/3`).
   - Example:
     ```elixir
     def delta_encode_counter(values) do
       {deltas, _} = Enum.reduce(values, {[], nil}, fn val, {acc, prev} ->
         case prev do
           nil -> {acc ++ [val], val}
           _ -> {acc ++ [val - prev], val}
         end
       end)
       deltas
     end
     ```

3. **Layered Compression**:
   - Support Zstandard via an optional `zstd: boolean` flag, using the `zstd` Hex package (`{:zstd, "~> 0.2.0"}`).
   - Fall back to existing `:zlib.gzip/1` if Zstd is unavailable or `zstd: false`.
   - Example:
     ```elixir
     def compress_layer(data, opts) do
       if Keyword.get(opts, :zstd, false) && Code.ensure_loaded?(Zstd) do
         Zstd.compress(data)
       else
         if Keyword.get(opts, :zlib, false), do: :zlib.gzip(data), else: data
       end
     end
     ```

4. **Integration**:
   - Modify `compress/2` to handle a `victoria_metrics: boolean` flag:
     ```elixir
     def compress(data, opts \\ []) do
       victoria_metrics? = Keyword.get(opts, :victoria_metrics, false)
       is_counter? = Keyword.get(opts, :is_counter, false)
       # ... existing Gorilla logic ...
       {values, metadata} =
         if victoria_metrics? do
           intermediate = if is_counter?, do: delta_encode_counter(values), else: values
           scale_floats_to_ints(intermediate)
         else
           {values, 0}
         end
       # ... apply XOR, compress_layer, store metadata ...
     end
     ```
   - Update `decompress/2` to reverse steps (unscale, reverse deltas) when `victoria_metrics: true`.

### Dependencies
- **Required**: None for core enhancements (float scaling, counter deltas) — use Elixir standard library (`Kernel`, `Enum`, `Bitwise`).
- **Optional**: Add `{:zstd, "~> 0.2.0"}` for Zstd support. If not included, fall back to `:zlib.gzip/1` (already used).

### Expected Benefits
- **Compression Ratios**: 2-5x improvement for gauges (via scaling), 2-5x for counters (via deltas), 1.5-2x from Zstd vs. zlib (per VictoriaMetrics benchmarks).
- **Performance**: Minimal CPU overhead (O(n) preprocessing); Zstd is faster than zlib.
- **Compatibility**: Fully lossless, preserves existing Gorilla functionality when flag is off.

## Acceptance Criteria
- Add `victoria_metrics: boolean` flag to `compress/2` and `decompress/2`.
- Implement float-to-integer scaling and counter delta encoding using standard library.
- Support `zstd: boolean` flag with fallback to existing zlib.
- Ensure lossless compression (round-trip data integrity).
- Add tests for:
  - Gauge series (e.g., `[1.23, 4.56, 7.89]`) with scaling.
  - Counter series (e.g., `[100, 110, 125]`) with delta encoding.
  - Compression ratio improvements (compare sizes with/without flag).
- Update docs for new flags and optional Zstd dependency.

## Notes
- Consider heuristic for `is_counter` (e.g., `Enum.all?(Enum.chunk_every(values, 2, 1, :discard), fn [a, b] -> b >= a end)`) if not explicitly flagged.
- Benchmark compression ratios and CPU usage on sample time-series data.
- If Zstd dependency is undesirable, zlib fallback should suffice for most gains.

## References
- VictoriaMetrics source: [github.com/VictoriaMetrics/VictoriaMetrics](https://github.com/VictoriaMetrics/VictoriaMetrics) (see `lib/storage/encoding.go`).
- Zstd Hex package: [hex.pm/packages/zstd](https://hex.pm/packages/zstd).

---

You can copy this Markdown directly into your project’s issue tracker. It provides a clear scope, technical guidance, and actionable steps for a developer to implement the feature. If you need adjustments (e.g., specific project conventions, additional test cases, or integration with a particular module), let me know!
