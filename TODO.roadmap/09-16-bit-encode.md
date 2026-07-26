# 09 - 16-bit encode support

- **Priority**: P2
- **Status**: Done

## Context

`encode_standard` hardcoded `bit_depth=8`. Some scientific imaging and
photography workflows require 16-bit per channel for higher dynamic
range.

## Approach

New option on `Libpng::StandardEncoder`:

```ruby
bit_depth: 8 | 16
```

The encoder:
1. Validates `bit_depth` is 8 or 16 (or 8 only for `:ga` / `:palette`).
2. Passes the bit_depth to `png_set_IHDR`.
3. Computes `stride = width * channels * (bit_depth == 16 ? 2 : 1)`
   via `Libpng::BytesPerPixel.for_color_type(color_type, bit_depth:)`.

Caller is responsible for providing 2 bytes per channel
(host-order little-endian on x86/arm -- the typical convention).

## New helper

`Libpng::BytesPerPixel.for_color_type(color_type, bit_depth: 8)` --
maps a `PNG_COLOR_TYPE_*` plus bit depth to bytes per pixel. Uses the
`CHANNELS_BY_COLOR_TYPE` table and `CHANNEL_BYTES_8_BIT` /
`CHANNEL_BYTES_16_BIT` constants.

## Specs

- bit_depth: 8 (default) -- verify IHDR
- bit_depth: 16 -- verify IHDR has bit_depth=16
- bit_depth: 16 with palette format -- reject (palette is always 8)
- bit_depth: 12 -- reject (only 8 and 16 supported)

## Delivered

PR #7 (this branch).

## Future work

- `convert_to_16bit:` on `encode` (simplified API) -- currently only
  `convert_to_8bit:` exists.
- 16-bit decode: `decode` currently always produces 8-bit output even
  when the source PNG is 16-bit. This is libpng's simplified API
  behavior.
