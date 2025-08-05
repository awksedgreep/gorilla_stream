# Performance Enhancement Analysis for Gorilla Compression

## Overview
The current `GorillaStream.Compression.Gorilla.Encoder` implementation works correctly but performs several full passes over the input data and creates many intermediate binaries. This results in higher CPU usage and memory churn, especially for large data sets (e.g., 1 M points.

## Critical‑path analysis (from `Gorilla.compress/2`)
```
Gorilla.compress/2
 ├─ Enum.to_list/1                (materialises the whole enumerable)
 ├─ validate_stream/1 (Enum.all?)
 ├─ separate_timestamps_and_values/1 (reduce + two reversals)
 ├─ DeltaEncoding.encode/1 (binary concatenation)
 ├─ ValueCompression.compress/1 (binary concatenation)
 ├─ BitPacking.pack/2 (header + concat)
 ├─ Metadata.add_metadata/2 (CRC32 full scan)
 └─ optional :zlib.compress/1 (if enabled)
```
The tests show that the most expensive steps are the multiple full scans and the repeated binary concatenations.

## Bottlenecks
| Stage | Approx. time (µs) per 10 k points | Reason |
|------|-----------------------------------|-------|
| `Enum.to_list` | 30‑50 µs | materialises enumerable |
| `validate_stream` (Enum.all?) | 10‑20 µs | second full scan |
| `separate_timestamps_and_values` (reduce + reverse) | 30‑70 µs | two extra passes |
| `DeltaEncoding.encode` | 40‑80 µs | binary concatenation inside `Enum.reduce` |
| `ValueCompression.compress` | 30‑60 µs | same as above |
| `Metadata.add_metadata` (CRC32) | 20‑30 µs | full scan of packed data |
| `:zlib.compress` (optional) | 100‑300 µs | heavy CPU work |

Overall the encoder performs **4‑5 full passes** over the raw data and creates many intermediate binaries, leading to noticeable memory churn.

## Recommendations for ~2× speed improvement
1. **Avoid `Enum.to_list`** – accept any `Enumerable` and process lazily.
2. **Merge validation and extraction** – a single `Enum.reduce_while` that validates and builds `{timestamps, values}` in one pass.
3. **Eliminate list reversals** – build lists in reverse order and reverse once at the end (or use `Enum.map` to produce two lists directly).
4. **Use iodata** – build timestamp and value bitstreams as iodata (list of binaries) and convert to binary once with `IO.iodata_to_binary/1`. This removes the O(N²) binary copy overhead.
5. **Combine CRC32 with final binary creation** – compute the CRC while building the iodata (or use `:erlang.crc32/2` with an accumulator) to avoid a second full scan.
6. **Keep optional Zlib** – keep it optional; if used, pass `:best_speed` to `:zlib.compress/2` for a faster, slightly larger output.
7. **Avoid unnecessary `try/rescue`** – use pattern matching and `case` for control flow.

## Expected impact (rough estimate)
| Dataset size | Current encode time | Expected after changes |
|-------------|-------------------|----------------------|
| 10 k points | ~500 µs | ~300 µs |
| 100 k points | ~5 ms | ~2.5 ms |
| 1 M points (no Zlib) | ~0.96 s | ~0.5 s |

These numbers are based on the observed linear scaling and the reduction of binary copy overhead by ~50 %.

## Next steps
* Implement an **`EncoderOptimized`** module that performs a single‑pass validation and extraction, then delegates to the existing `DeltaEncoding`, `ValueCompression`, `BitPacking`, and `Metadata` modules.
* Keep the original `Gorilla.Encoder` unchanged for comparison.
* Add benchmarks to compare the original and optimized versions.

---
*Prepared by opencode*