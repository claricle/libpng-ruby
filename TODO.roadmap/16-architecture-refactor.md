# 16 - Architecture refactor: autoload + OOP

- **Priority**: P0
- **Status**: Done

## Context

`lib/libpng.rb` was a 466-line monolith mixing:
- Module definition
- FFI library setup
- 13 `attach_function` calls
- ~40 constants (FORMAT_*, COLOR_TYPE_*, FILTER_*, INTERLACE_*, etc.)
- `png_image` struct layout constants
- `encode`, `decode`, `encode_standard` methods (each 50-100 lines)
- 5 private helper methods

Plus the file used `require_relative 'libpng/version'`, violating the
project-wide rule against `require_relative` for internal library code.

## Approach

Split into MECE per-concern files under `lib/libpng/`, loaded via
`autoload` from `lib/libpng.rb`:

| File | Responsibility |
|---|---|
| `error.rb` | `Libpng::Error` |
| `decoded_image.rb` | `Libpng::DecodedImage` Struct |
| `chunk_walker.rb` | `Libpng::ChunkWalker` (PNG chunk walking utility class) |
| `bytes_per_pixel.rb` | `Libpng::BytesPerPixel` (pure-data lookup) |
| `simplified_encoder.rb` | `Libpng::SimplifiedEncoder` (encode via simplified API) |
| `simplified_decoder.rb` | `Libpng::SimplifiedDecoder` (decode + metadata extraction) |
| `standard_encoder.rb` | `Libpng::StandardEncoder` (encode_standard with all options) |

Each encoder/decoder is a class instantiated per call:
```ruby
class Libpng::SimplifiedEncoder
  def initialize(width, height, pixels, **opts)
    # validate + store
  end

  def call
    # do the work, return result
  end
end
```

The public API stays as module methods for backward compat:
```ruby
def self.encode(width, height, pixels, **opts)
  SimplifiedEncoder.new(width, height, pixels, **opts).call
end
```

## Why per-call instances

- **OCP**: New encode options (e.g. `gamma:`) extend the encoder class
  without touching `Libpng.encode`.
- **Testability**: Each encoder is independently testable.
- **MECE**: Validation lives in the encoder, FFI calls live in the
  encoder, dispatch lives in the module. Three concerns, three places.
- **Ractor-safe by construction**: Instances are local to one call,
  never shared.

The per-call allocation cost (~1 object) is negligible compared to the
libpng C call.

## Why autoload instead of eager

- Faster `require 'libpng'` for users who only need one API
- Project rule: never `require_relative` for internal library code
- Lazy loading of rarely-used classes (e.g. `Recipe` is only needed
  during source-gem install)

## What changed in ext/extconf.rb

Before:
```ruby
$LOAD_PATH << File.expand_path('../lib', __dir__)
require 'libpng/recipe'  # violation: require with path
```

After:
```ruby
$LOAD_PATH << File.expand_path('../lib', __dir__)
require 'libpng'  # triggers autoload setup
recipe = Libpng::Recipe.new  # accesses Recipe constant, triggers autoload
```

## Specs

All existing specs still pass without modification (the public API is
unchanged). 81 examples, 0 failures.

## Delivered

PR #7 (this branch).
