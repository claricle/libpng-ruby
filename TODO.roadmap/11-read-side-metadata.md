# 11 - Read-side metadata getters

- **Priority**: P2
- **Status**: Done

## Context

`Libpng::DecodedImage` returned only `width`, `height`, `format`, and
`pixels`. Callers wanting bit_depth, color_type, or interlace method
had to walk the PNG themselves.

## Approach

Two pieces:

1. **Expanded Struct**: `Libpng::DecodedImage` now has `bit_depth`,
   `color_type`, `interlace` keyword fields (in addition to the
   existing four).

2. **`Libpng::ChunkWalker`**: new public class for walking PNG chunk
   layout. Methods:
   - `#each_chunk` -- yields `[type, data, offset]`
   - `#strip_ancillary` -- returns a new binary String with only
     IHDR/IDAT/IEND (used by SimplifiedEncoder when `strip_colorspace:
     true`)
   - `#ihdr_data` -- raw IHDR bytes
   - `#ihdr_fields` -- parsed Hash: `:width, :height, :bit_depth,
     :color_type, :compression, :filter, :interlace`

3. **`Libpng::SimplifiedDecoder`** uses `ChunkWalker#ihdr_fields` after
   the libpng decode to populate the new Struct fields. Best-effort:
   if the walker raises (e.g. corrupt PNG), the metadata stays nil and
   the libpng-side error propagates.

## Refactor side-effect

The chunk-stripping logic in `Libpng::SimplifiedEncoder` was rewritten
to use `ChunkWalker#strip_ancillary` instead of inline code. DRY win:
one place that understands PNG chunk layout.

## Specs

`spec/decoded_image_metadata_spec.rb` verifies:
- IHDR metadata is populated for RGBA/RGB/GRAY decode
- Adam7 interlace is reflected after `encode_standard(interlace:
  :adam7)` -> decode
- `ChunkWalker` parses IHDR fields correctly
- `ChunkWalker` raises `FormatError` on non-PNG input

## Delivered

PR #7 (this branch).

## Future work

- Expose text chunks (tEXt/zTXt/iTXt) -- see [TODO 19](19-text-chunk-read.md)
- Expose color metadata (gAMA/cHRM/sRGB/iCCP) -- see [TODO 20](20-color-metadata-read.md)
- Ancillary chunk preservation on decode (currently we expand to
  pixels and drop everything else)
