# 07 - interlace: option on encode_standard

- **Priority**: P1
- **Status**: Done

## Context

`encode_standard` hardcoded `INTERLACE_NONE`. Some use cases (progressive
image loading for web) require Adam7 interlacing.

## Approach

New option on `Libpng::StandardEncoder`:

```ruby
interlace: :none | :adam7
```

Constants already defined in `lib/libpng.rb` (`INTERLACE_NONE`,
`INTERLACE_ADAM7`). Added `INTERLACE_BY_NAME` lookup table for
symbol-to-constant mapping.

Validation: rejects unknown symbols with a clear error.

Specs in `spec/standard_encoder_options_spec.rb`:
- Default is `:none` (verify via IHDR walk)
- `:adam7` produces IHDR with `interlace=INTERLACE_ADAM7`
- Adam7 output is larger than :none for small images (per-pass
  overhead exceeds compression savings)
- Round-trips through `Libpng.decode` to the original pixels

## Delivered

PR #7 (this branch).

## Why not also add to encode (simplified API)?

libpng's simplified API doesn't expose interlace control -- it always
emits non-interlaced PNGs. Adding it there would require a separate
write path, which is what `encode_standard` already is.
