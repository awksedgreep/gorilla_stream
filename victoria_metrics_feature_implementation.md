# Multi-Phase Implementation Guide: VictoriaMetrics-Style Compression Flag

This guide outlines the steps to add optional VictoriaMetrics-style compression to GorillaStream as a feature flag, building on the existing Gorilla algorithm. The goal is to enable improved compression ratios while preserving full backward compatibility and minimizing risk.

Primary reference: victoria_metrics_compression_feature_request.md


## Current architecture (context)

- Public API
  - GorillaStream.Compression.Gorilla.compress(stream, zlib? \\ false)
  - GorillaStream.Compression.Gorilla.decompress(binary, zlib? \\ false)
- Pipeline (encode)
  - GorillaStream.Compression.Gorilla.Encoder
    - separates timestamps/values
    - timestamps via Encoder.DeltaEncoding
    - values via Encoder.ValueCompression (XOR-based)
    - combined via Encoder.BitPacking (32-byte inner header)
    - metadata header via Encoder.Metadata (80-byte outer header, version=1, flags reserved)
- Pipeline (decode)
  - GorillaStream.Compression.Gorilla.Decoder
    - metadata via Decoder.Metadata (80-byte outer header)
    - split via Decoder.BitUnpacking (mirrors the 32-byte inner header)
    - values via Decoder.ValueDecompression (XOR-based)
    - timestamps via Decoder.DeltaDecoding
- Final container compression
  - Optional :zlib.compress / :zlib.uncompress applied around the entire encoded payload via Gorilla.compress/2 and Gorilla.decompress/2


## Goals

- Add a victoria_metrics: true flag to opt in to a preprocessing pipeline inspired by VictoriaMetrics, while keeping Gorilla default unchanged when the flag is off.
- Preprocessing when enabled:
  - Optional monotonic counter delta encoding for values (is_counter: true | heuristic)
  - Float-to-integer scaling by 10^N (N auto-detected or provided) for better XOR compressibility
- Optional final container compression with Zstandard when zstd: true and dependency present; otherwise fall back to existing zlib or none.
- Persist enough metadata to fully reverse preprocessing during decompression.
- Preserve backward compatibility for:
  - Existing boolean arg form compress(stream, zlib?) and decompress(binary, zlib?)
  - Existing metadata header v1


## Non-goals

- Changing the Gorilla value/timestamp bit-level format (we layer on top via preprocessing and metadata).
- Introducing required external deps (Zstd remains optional).


## Phase 0 – Design and API compatibility

1) Public API shape (back-compat + new opts)
   - Keep the existing arity for callers: compress(stream, zlib? \\ false) and decompress(binary, zlib? \\ false)
   - Add keyword-opts arity and delegate between them to preserve compatibility:
     - compress(stream, opts \\ []): accepts victoria_metrics, is_counter, scale_decimals, zstd, zlib
     - decompress(binary, opts \\ []): same options; but prefer auto-detection via metadata flags
   - Boolean arity stays as a thin wrapper to opts for one release, deprecate later via @doc and @deprecated notes.

2) Options and defaults
   - victoria_metrics: false (opt-in)
   - is_counter: false (opt-in). If not set and victoria_metrics: true, offer heuristic: detect monotonic non-decreasing values; can be disabled explicitly.
   - scale_decimals: :auto (or integer 0..9). Default :auto with sensible cap (e.g., 0..6) to avoid float precision pitfalls.
   - zstd: false (opt-in). Only used if Code.ensure_loaded?(Zstd).
   - zlib: false (existing behavior). If both zstd and zlib are false, no final container compression is applied.

3) Auto-detect compression on decompress
   - New default decompress(binary, opts \\ []) ignores zlib? param and reads the header flags to determine if zstd/zlib were used.
   - Keep decompress(binary, boolean) as back-compat; when flags present, prefer flags over boolean.

Deliverables
- Updated moduledocs, specs, and deprecation notes.


## Phase 1 – Value preprocessing utilities

Add: GorillaStream.Compression.Enhancements (new module)

Responsibilities
- scale_floats_to_ints/2
  - Input: list of numbers (floats or ints), scale_decimals: integer | :auto
  - Determine N (max decimals) when :auto (capped, e.g., 6). Use a robust heuristic to avoid floating point artifacts (e.g., round to N with :erlang.float_to_binary/2 or decimal-string inspection) and return {scaled_ints, N}.
- delta_encode_counter/1 and delta_decode_counter/1
  - values -> [first, delta1, delta2, ...]
  - inverse reconstructs original series
- is_monotonic_non_decreasing?/1 (heuristic)

Performance and correctness notes
- All steps O(n); avoid extra allocations (prefer reduce/accumulate).
- Return PreprocessMetadata struct or map: %{scale_decimals: N, is_counter: bool}
- No IO.puts/IO.inspect; use Logger.debug for temporary diagnostics if needed and keep logging minimal/off by default.

Deliverables
- New module with unit tests for each function.


## Phase 2 – Encoder integration (opt-in path)

Changes to GorillaStream.Compression.Gorilla.Encoder (and caller)
- Keep existing encode path unchanged when victoria_metrics: false.
- When victoria_metrics: true:
  1) Separate timestamps/values (existing function)
  2) If is_counter or heuristic says so: values = delta_encode_counter(values), tag metadata
  3) {values, N} = scale_floats_to_ints(values, scale_decimals)
  4) Continue through ValueCompression.compress(values) as-is (it already accepts ints coerced to floats internally).
- Thread additional metadata forward so it can be persisted:
  - In BitPacking.pack combined_metadata, add a pass-through map like :vm_meta => %{scale_decimals: N, is_counter: bool, victoria_metrics: true}

Touch points
- GorillaStream.Compression.Gorilla.compress/2 or /1 opts: gather opts and pass down to Encoder.
- Minimal/no change to ValueCompression and DeltaEncoding bit-level algorithms.

Deliverables
- Updated encode pipeline with opts parameterization and VM metadata threading.


## Phase 3 – Metadata/header upgrade (outer 80-byte header -> v2)

Objective
- Persist flags and scale_decimals to enable full reversal during decode.

Plan
- Bump outer metadata header version from 1 -> 2 in Encoder.Metadata and Decoder.Metadata.
- Maintain compatibility with v1 on decode.
- Reuse existing 32-bit flags field (currently reserved) and add a small extension block to carry scale_decimals.

Flags (32-bit bitfield)
- 0x00000001: victoria_metrics_enabled
- 0x00000002: is_counter
- 0x00000004: zstd_applied
- 0x00000008: zlib_applied
- Remaining bits reserved for future use

Header length and extension
- Keep the original 80-byte layout for v1.
- For v2, set header_length to 84 and append:
  - scale_decimals::32 (unsigned integer; if 0, means no scaling; else N)
- Checksum logic stays the same (computed over packed compressed payload after the outer header).

Encoder.Metadata
- Add ability to build v2 header when vm_meta present (victoria_metrics true) or zstd selected; otherwise continue to emit v1 for perfect back-compat when feature unused.
- Populate flags as above; write scale_decimals when header v2 is used.

Decoder.Metadata
- Accept v1 (header_length == 80): treat as flags=0, scale_decimals=0
- Accept v2 (header_length == 84): parse extra 32-bit scale_decimals
- Return parsed flags and scale_decimals in the metadata map (e.g., under :flags and :vm_meta)

Deliverables
- Versioned header encode/decode with tests covering both v1 and v2.


## Phase 4 – Final container compression selection (zstd | zlib | none)

Objective
- Generalize final compression layer from boolean zlib to an options-based selector.

Implementation
- In Gorilla.compress:
  - Introduce apply_container_compression(data, opts) that:
    - when Keyword.get(opts, :zstd, false) && Code.ensure_loaded?(Zstd) -> Zstd.compress(data)
    - else if Keyword.get(opts, :zlib, false) -> :zlib.compress(data)
    - else -> data
  - Set flags in header accordingly (zstd_applied or zlib_applied)

- In Gorilla.decompress:
  - Prefer header flags to determine decompression path (zstd or zlib); only fall back to boolean param for legacy payloads without flags.

Dependency
- Add optional {:zstd, "~> 0.2.0"} to mix.exs (no runtime requirement if unused). Guard calls with Code.ensure_loaded?(Zstd).

Deliverables
- Container compression selector + metadata flagging + decode auto-detection.


## Phase 5 – Decoder integration for VictoriaMetrics pipeline

When metadata.flags has victoria_metrics_enabled:
1) Run the normal bit unpacking + ValueDecompression and DeltaDecoding.
2) Grab vm_meta: %{scale_decimals: N, is_counter: bool}
3) Post-process values:
   - If N > 0: unscale by dividing by 10^N
   - If is_counter: reverse counter deltas to reconstruct original series
4) Zip timestamps and values and return.

Edge handling
- Ensure lengths stay equal; error if mismatch.
- Validate monotonic counter invariants only if helpful (optional; avoid runtime penalty by default).

Deliverables
- Decode branch keyed off flags with comprehensive tests.


## Phase 6 – Tests and property checks

Unit tests
- Enhancements
  - scale_floats_to_ints round-trip: values -> scale -> XOR path -> unscale == values (within tolerance if needed)
  - delta_encode_counter then delta_decode_counter restores original list
  - monotonic heuristic examples (true/false)
- Header v1/v2
  - Encode v1 when feature unused; decode unchanged
  - Encode v2 when vm or zstd used; parse flags and scale_decimals
- Compress/decompress end-to-end
  - victoria_metrics: true with is_counter: true and scale_decimals: explicit
  - victoria_metrics: true with heuristic counter and scale_decimals: :auto
  - victoria_metrics: false (baseline unchanged)
- Container compression
  - zstd path when available (skipped if dependency absent), zlib path, and none

Property tests (where helpful)
- Round-trip identity for random monotonic counters and random gauges with bounded decimals
- No panics on empty or singleton series

Performance assertions
- Optional size comparisons to demonstrate better ratios when VM flag is on for typical data shapes.


## Phase 7 – Docs and examples

- README.md
  - Brief section introducing the VictoriaMetrics-style flag, with simple examples.
- docs/user_guide.md
  - New options table and examples:
    - victoria_metrics, is_counter, scale_decimals, zstd, zlib
  - Decompression auto-detection behavior
- docs/performance_guide.md
  - How scaling and counter deltas improve XOR compressibility; guidance on choosing scale_decimals
- Moduledocs
  - Update Gorilla.compress/2 and decompress/2 docs with new opts and back-compat notes

Note on logging
- Follow project rule: do not use IO.puts/IO.inspect; use Logger.debug/info as needed, guarded or minimal in hot paths.


## Phase 8 – Benchmarks and rollout

- Extend existing scripts/tests to run before/after comparisons on representative datasets (gauges and counters).
- Add a Mix task toggle or config helper in GorillaStream.Config to recommend enabling VM flag when data is a good fit.
- Release management
  - Semver minor bump for new feature (no breaking changes); consider patch if truly additive.
  - Changelog entries and migration note (API remains compatible; opts preferred going forward).


## Risks, edge cases, mitigations

- Float precision and scale detection
  - Cap :auto scale_decimals; allow explicit override
  - Prefer decimal-string inspection for determining max decimals, not naive arithmetic on floats
- Heuristic misclassification (is_counter)
  - Default to explicit flag; heuristic only when requested
- Header compatibility
  - Decode both v1 and v2; only emit v2 when feature used
- Optional dependency not present
  - zstd guarded with Code.ensure_loaded?(Zstd); fallback to zlib or none
- Performance regressions
  - Preprocessing is O(n); ensure single-pass where possible; avoid intermediate lists via reduce


## Acceptance criteria (mirrors feature request)

- compress/2 and decompress/2 accept victoria_metrics: boolean (default false)
- When enabled:
  - Float-to-integer scaling with stored scale_decimals (N)
  - Optional counter delta encoding reversible on decode
  - Optional zstd final compression with metadata flags and fallback to zlib/none
- Lossless round-trip for gauges and counters
- Header v1/v2 coexistence; flags correctly parsed; scale_decimals persisted when present
- Tests cover:
  - Gauges with scaling
  - Counters with delta encoding
  - Compression ratio improvements (informational assertions)
  - Legacy API still works
- Docs updated; Logger used for any diagnostics


## Implementation sketch (selected snippets)

Note: These are illustrative and should be adapted to final code locations/names.

Enhancements module

```elixir
# lib/gorilla_stream/compression/enhancements.ex
defmodule GorillaStream.Compression.Enhancements do
  @spec scale_floats_to_ints([number()], integer() | :auto) :: {[integer()], non_neg_integer()}
  def scale_floats_to_ints(values, :auto), do: scale_floats_to_ints(values, detect_scale(values))
  def scale_floats_to_ints(values, n) when is_integer(n) and n >= 0 do
    scale = :math.pow(10, n) |> round()
    scaled = Enum.map(values, fn v -> trunc(Float.round(v * 1.0 * scale, 0)) end)
    {scaled, n}
  end

  @spec detect_scale([number()]) :: non_neg_integer()
  def detect_scale(values) do
    values
    |> Enum.reduce(0, fn v, acc -> max(acc, decimals_for(v)) end)
    |> min(6)
  end

  defp decimals_for(v) do
    s = :erlang.float_to_binary(v * 1.0, [:compact, {:decimals, 10}])
    case String.split(s, ".") do
      [_i, frac] -> String.trim_trailing(frac, "0") |> String.length()
      _ -> 0
    end
  end

  @spec delta_encode_counter([number()]) :: [number()]
  def delta_encode_counter([]), do: []
  def delta_encode_counter([h | t]) do
    {deltas, _} =
      Enum.reduce(t, {[h], h}, fn x, {acc, prev} -> {[x - prev | acc], x} end)
    Enum.reverse(deltas)
  end

  @spec delta_decode_counter([number()]) :: [number()]
  def delta_decode_counter([]), do: []
  def delta_decode_counter([h | t]) do
    {vals, _} =
      Enum.reduce(t, {[h], h}, fn d, {acc, prev} -> v = prev + d; {[v | acc], v} end)
    Enum.reverse(vals)
  end

  @spec monotonic_non_decreasing?([number()]) :: boolean()
  def monotonic_non_decreasing?([]), do: true
  def monotonic_non_decreasing?([_]), do: true
  def monotonic_non_decreasing?([a, b | rest]) do
    if b < a, do: false, else: monotonic_non_decreasing?([b | rest])
  end
end
```

Header v2 example (Encoder.Metadata additions)

```elixir
# Pseudocode: when building header
flags = 0
flags = if vm_enabled, do: flags ||| 0x1, else: flags
flags = if is_counter, do: flags ||| 0x2, else: flags
flags = if zstd?, do: flags ||| 0x4, else: flags
flags = if zlib?, do: flags ||| 0x8, else: flags

if vm_enabled or zstd? do
  # emit v2 (header_length = 84) and append scale_decimals::32 after existing fields
else
  # emit v1 (header_length = 80)
end
```

Decompression selection

```elixir
# Pseudocode in Gorilla.decompress/2
case read_flags_from_header(binary) do
  {:ok, flags} ->
    cond do
      (flags &&& 0x4) != 0 -> data = Zstd.decompress(rest)
      (flags &&& 0x8) != 0 -> data = :zlib.uncompress(rest)
      true -> data = rest
    end
  :no_flags ->
    # legacy behavior controlled by boolean param
end
```


## Files to touch (overview)

- lib/gorilla_stream/compression/gorilla.ex
  - Public API arities, opts plumbing, final compression selection
- lib/gorilla_stream/compression/gorilla/encoder.ex
  - Accept opts; call Enhancements when victoria_metrics true
- lib/gorilla_stream/compression/gorilla/decoder.ex
  - Post-process values (unscale + delta-decode) keyed off flags
- lib/gorilla_stream/compression/encoder/bit_packing.ex
  - Thread vm_meta if needed (no format change)
- lib/gorilla_stream/compression/encoder/metadata.ex
  - Header v2 write: flags + scale_decimals
- lib/gorilla_stream/compression/decoder/metadata.ex
  - Header v2 parse; expose flags + scale_decimals
- lib/gorilla_stream/compression/enhancements.ex (new)
  - Preprocessing helpers
- mix.exs
  - Optional {:zstd, "~> 0.2.0"}
- docs and tests as described


## Next steps

- Implement Phase 0–3 behind feature flags; ship as a small PR chain or one guarded PR.
- Add tests and docs; run existing test suite to ensure no regressions.
- Optionally add a mix profile to include :zstd only in environments that need it.


---

This plan is tailored to the current GorillaStream layout and preserves existing behaviors when the feature is disabled. It introduces minimal surface area changes, leverages the existing reserved flags in the header, and keeps optional dependencies optional. If you’d like, I can implement Phases 0–3 in a PR-ready branch next.

