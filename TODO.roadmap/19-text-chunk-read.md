# 19 - Text chunk (tEXt/zTXt/iTXt) read support

- **Priority**: P2
- **Status**: Planned

## Context

PNG images often carry metadata in text chunks:
- `tEXt`: Latin-1 key/value pairs
- `zTXt`: zlib-compressed Latin-1
- `iTXt`: UTF-8 with optional compression, optional language tag

Common keys: `Title`, `Author`, `Description`, `Copyright`,
`Software`, `Creation Time`.

Our `ChunkWalker` already iterates all chunks. We just need to parse
the text chunk format and expose it on `DecodedImage`.

## Proposal

Extend `Libpng::ChunkWalker` with text-chunk parsing, and extend
`DecodedImage` to carry a `text` field.

```ruby
decoded = Libpng.decode(File.binread("photo.png"), pixel_format: "RGB")
decoded.text           # => { "Title" => "Sunset", "Author" => "Jane", ... }
decoded.text["Title"]  # => "Sunset"
```

Text values are UTF-8 strings (converted from Latin-1 for tEXt/zTXt;
already UTF-8 for iTXt). Keys are ASCII.

## Implementation

Add to `chunk_walker.rb`:

```ruby
def text_chunks
  result = {}
  each_chunk do |type, data, _|
    case type
    when 'tEXt' then parse_text(data, result)
    when 'zTXt' then parse_ztxt(data, result)
    when 'iTXt' then parse_itxt(data, result)
    end
  end
  result
end

private

def parse_text(data, result)
  null_idx = data.index("\x00")
  return if null_idx.nil?
  key = data[0, null_idx]
  val = data[(null_idx + 1)..]
  result[key] = val.force_encoding('ISO-8859-1').encode('UTF-8')
end

def parse_ztxt(data, result)
  null_idx = data.index("\x00")
  return if null_idx.nil?
  key = data[0, null_idx]
  # data[null_idx+1] is compression method (0 = zlib)
  compressed = data[(null_idx + 2)..]
  val = Zlib.inflate(compressed)
  result[key] = val.force_encoding('ISO-8859-1').encode('UTF-8')
end

def parse_itxt(data, result)
  # iTXt is more complex: keyword\0 compression_flag compression_method
  # language_tag\0 translated_keyword\0 text
  # ... parse accordingly
end
```

Then in `simplified_decoder.rb`:

```ruby
metadata = extract_metadata
text = ChunkWalker.new(@png).text_chunks rescue {}
return DecodedImage.new(..., text: text)
```

And in `decoded_image.rb`:

```ruby
DecodedImage = Struct.new(:width, :height, :format, :pixels,
                          :bit_depth, :color_type, :interlace, :text,
                          keyword_init: true)
```

## Specs

- Round-trip: encode a PNG with tEXt chunks (via libpng's standard API,
  once we expose `png_set_text`), decode, verify text matches.
- zTXt decompression works.
- iTXt UTF-8 round-trip.
- Malformed text chunk doesn't break decode (best-effort).

## Out of scope

- Writing text chunks (`png_set_text`) -- separate TODO if needed.
- International text chunk ordering / precedence rules.
