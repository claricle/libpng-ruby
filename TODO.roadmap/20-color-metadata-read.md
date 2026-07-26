# 20 - Color metadata read (gAMA/cHRM/sRGB/iCCP)

- **Priority**: P2
- **Status**: Done

## Context

Color-managed PNG workflows rely on the gamma and chromaticity chunks:
- `gAMA`: image gamma (single uint32, scaled by 100000)
- `cHRM`: primary chromaticities (8 uint32s)
- `sRGB`: rendering intent (single byte, 0-3)
- `iCCP`: embedded ICC color profile (compressed)

The simplified API drops these on decode (it converts to the
requested output format directly). Callers who need to preserve color
metadata have to walk the chunks themselves.

## Proposal

Extend `Libpng::ChunkWalker` with color-chunk parsing, and extend
`DecodedImage` to carry a `color` field.

```ruby
decoded = Libpng.decode(File.binread("photo.png"), pixel_format: "RGB")
decoded.color         # => { gamma: 0.45455, srgb_intent: 0 }
decoded.color[:gamma] # => 0.45455
```

For ICC profiles, return the decompressed profile bytes (the user
parses with a separate ICC library).

## Implementation

Add to `chunk_walker.rb`:

```ruby
def color_chunks
  result = {}
  each_chunk do |type, data, _|
    case type
    when 'gAMA' then result[:gamma] = parse_gama(data)
    when 'cHRM' then result.merge!(parse_chrm(data))
    when 'sRGB' then result[:srgb_intent] = data.getbyte(0)
    when 'iCCP' then result[:icc_profile] = parse_iccp(data)
    end
  end
  result
end

private

def parse_gama(data)
  # Gamma is stored as uint32 * 100000.
  data.unpack1('N') / 100_000.0
end

def parse_chrm(data)
  wp_x, wp_y, red_x, red_y, green_x, green_y, blue_x, blue_y = data.unpack('N8')
  {
    white_point_x: wp_x / 100_000.0,
    white_point_y: wp_y / 100_000.0,
    red_x: red_x / 100_000.0, red_y: red_y / 100_000.0,
    green_x: green_x / 100_000.0, green_y: green_y / 100_000.0,
    blue_x: blue_x / 100_000.0, blue_y: blue_y / 100_000.0
  }
end

def parse_iccp(data)
  null_idx = data.index("\x00")
  return nil if null_idx.nil?
  # data[null_idx+1] is compression method (0 = zlib)
  Zlib.inflate(data[(null_idx + 2)..])
end
```

Extend `simplified_decoder.rb` to populate the `color:` field.

## Caveats

- gAMA without sRGB usually means the image is in some non-sRGB gamma
  space (e.g. 2.2). The simplified API does NOT gamma-correct on
  decode by default; pixels come through unchanged.
- iCCP profiles can be large (10KB-1MB). Returning them in the
  `DecodedImage` adds memory pressure. Provide a way to skip iCCP
  parsing (`parse_icc: false` option?).

## Specs

- Encode a PNG with `png_set_gAMA` (need standard-API binding), decode,
  verify gamma round-trips.
- sRGB chunk parsing.
- ICC profile decompression matches the original bytes.
- Color metadata absent -> empty Hash.

## Out of scope

- Writing color metadata (`png_set_gAMA`, etc.) on encode_standard.
  Separate TODO if a use case emerges.
- Color space conversion (e.g. apply gamma on decode). That's a
  separate library's job.
