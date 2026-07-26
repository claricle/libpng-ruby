# 08 - Palette support

- **Priority**: P2
- **Status**: Done

## Context

Report item #6: `encode_standard` only supported direct-color formats
(GRAY, GA, RGB, RGBA). Indexed-color images (1-bpp MONOPATTERN brushes
in EMF, indexed-color sprites, simple icons) compress much better as
`PNG_COLOR_TYPE_PALETTE` than as RGBA.

## Approach

New `pixel_format: :palette` mode on `Libpng::StandardEncoder`:

```ruby
Libpng.encode_standard(width, height, indices,
                       pixel_format: :palette,
                       palette: [[r, g, b], ...])  # or [r, g, b, a]
```

The encoder:
1. Validates the palette (1..256 entries; each `[r,g,b]` or `[r,g,b,a]`
   with 0..255 values).
2. Always uses `bit_depth=8` for palette format (1/2/4-bit packed
   indices are possible but require row stride juggling that's not
   worth the complexity for v1).
3. Calls `png_set_PLTE` with the RGB bytes.
4. If any palette entry has alpha, calls `png_set_tRNS` with the alpha
   values.

New FFI bindings attached:
- `png_set_PLTE` -- `[:pointer, :pointer, :pointer, :int], :void`
- `png_set_tRNS` -- `[:pointer, :pointer, :pointer, :int, :pointer], :void`

The tRNS 5th arg is `png_color_16p trans_color` -- pass NULL (nil).

Specs verify:
- Palette PNG round-trips via RGBA decode (each index expands to its
  palette color)
- Alpha entries are accepted
- Missing palette, oversized palette, malformed entries all raise

## Delivered

PR #7 (this branch).

## Future work

- 1/2/4-bit packed palette indices for smaller files. Requires row
  stride changes and is niche.
- Palette extraction on decode (currently `decode` always expands
  palette to RGBA/RGB).
