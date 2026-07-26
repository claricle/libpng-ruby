# 05 - Benchmarks for encode paths

- **Priority**: P1
- **Status**: Done

## Context

`encode_standard` was claimed to be ~3x faster than the original
Tempfile-based approach (per `REPORT-complex-api-needs.md`), but no
benchmark existed to verify or catch regressions.

## Approach

New spec file `spec/benchmark_spec.rb`. Three image sizes (16x16,
128x128, 512x512). For each:

- `Libpng.encode` (simplified, strip_colorspace on)
- `Libpng.encode_standard` (memory write)
- `Libpng.decode` (simplified, RGBA)

Measures median of 50 iterations using `Benchmark.realtime`. Prints
comparable numbers via `warn` so they show in CI logs but don't affect
test pass/fail.

Sanity assertions (not timing-based):
- Both PNGs start with `\x89PNG`
- Standard PNG decodes to the same pixels

Benchmarks are smoke tests, not performance gates. Specific timings
vary by machine and CI runner load; gating on absolute numbers would
be flaky.

## Delivered

PR #7 (this branch).

## Future work

- Add a `rake benchmark` task that runs only `spec/benchmark_spec.rb`
- Track benchmark results across releases (maybe via GitHub Actions
  artifacts) to spot performance regressions over time
