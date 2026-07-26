# 12 - Full libpng API surface binding

- **Priority**: Skip
- **Status**: Won't do

## Context

We expose 13 of libpng's 172 exported functions (~8%). The audit
(see PR #6 discussion) identified gaps in:

- Standard read API (10 functions)
- Write-side chunk setters (15+: PLTE, tRNS, gAMA, cHRM, sRGB, iCCP,
  bKGD, pHYs, oFFs, tIME, sCAL, sPLT, hIST, text, unknown chunks)
- Info getters (~20)
- Read transformations (~20)
- Advanced compression controls
- Progressive/streaming decode
- File I/O variants
- Filter heuristics
- Interlacing helpers
- CRC error handling
- Memory/struct internals

## Why we won't do this

1. **Scope creep**: The gem's purpose is encode/decode with libemf2svg
   parity, not a complete libpng binding.
2. **Maintenance cost**: Each function needs docs, tests, and version
   compatibility checks across libpng releases.
3. **Ractor safety risk**: Many libpng functions are stateful
   (`png_set_*` mutates `png_struct`). Exposing them naively could
   introduce Ractor-safety violations.
4. **Alternatives exist**: Users needing low-level libpng access can
   `attach_function` against the bundled `libpng16.so` directly
   (it contains all 172 functions).
5. **YAGNI**: No user has requested specific functions beyond what
   `encode_standard` provides.

## When this position might change

- A specific user need that can't be met by extending the existing
  options-based API.
- A major libpng release that introduces a high-demand feature
  (unlikely in the 1.6.x series).
- A formal request from emfsvg or another downstream consumer.

## Recommended path forward (if needed)

Instead of exposing `png_set_gAMA` etc. as individual Ruby methods,
add higher-level options to `encode_standard`:

```ruby
Libpng.encode_standard(width, height, pixels,
                       pixel_format: "RGBA",
                       gamma: 0.45455,         # emits gAMA
                       chromaticities: {...},  # emits cHRM
                       srgb: 0,                # emits sRGB
                       icc_profile: File.read("profile.icc"))  # emits iCCP
```

This keeps the API Ruby-idiomatic and limits the testing surface.
