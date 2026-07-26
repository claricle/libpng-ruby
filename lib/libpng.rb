# frozen_string_literal: true

require 'ffi'

# Libpng is a Ruby binding for libpng (the official PNG reference library)
# via FFI. The native library is pre-compiled for each target platform and
# shipped inside the gem, so no C compiler is required at install time.
#
# Public API:
#   Libpng.encode(width, height, rgba_bytes, pixel_format: "RGBA")
#   Libpng.encode_standard(width, height, rgba_bytes, pixel_format: "RGBA", ...)
#   Libpng.decode(png_bytes, pixel_format: "RGBA")
#
# All encode/decode state is per-call. Each call constructs a dedicated
# encoder or decoder instance, runs it, and discards it. Calls from
# different Ractors do not share state. The FFI function table
# (Libpng::Binding) loads lazily on first use and is shareable across
# Ractors.
module Libpng
  # Version constants live in lib/libpng/version.rb. Autoloaded so the
  # version file isn't loaded until someone references a version constant.
  autoload :LIBPNG_VERSION, 'libpng/version'
  autoload :LIBPNG_RUBY_ITERATION, 'libpng/version'
  autoload :VERSION, 'libpng/version'

  # Public-facing classes.
  autoload :Error, 'libpng/error'
  autoload :DecodedImage, 'libpng/decoded_image'
  autoload :ChunkWalker, 'libpng/chunk_walker'
  autoload :BytesPerPixel, 'libpng/bytes_per_pixel'
  autoload :SimplifiedEncoder, 'libpng/simplified_encoder'
  autoload :SimplifiedDecoder, 'libpng/simplified_decoder'
  autoload :StandardEncoder, 'libpng/standard_encoder'
  autoload :StandardDecoder, 'libpng/standard_decoder'
  autoload :TextWriter, 'libpng/text_writer'
  autoload :TextEntry, 'libpng/text_writer'
  autoload :MetadataWriter, 'libpng/metadata_writer'

  # FFI bindings. Autoloaded so that requiring `libpng` is cheap and
  # does not dlopen libpng16.{so,dylib,dll} -- ext/extconf.rb needs to
  # require 'libpng' to access Libpng::Recipe during the source-gem
  # build, at which point the shared library doesn't exist yet.
  autoload :Binding, 'libpng/binding'

  # Build-time recipe (MiniPortile). Only loaded when ext/extconf.rb
  # is invoked during `gem install` of the source ('ruby' platform) gem.
  autoload :Recipe, 'libpng/recipe'

  # ------------------------------------------------------------------
  # PNG_IMAGE_FORMAT_* bit flags (png.h). Used by the simplified API.
  # ------------------------------------------------------------------
  FORMAT_FLAG_ALPHA             = 0x01
  FORMAT_FLAG_COLOR             = 0x02
  FORMAT_FLAG_LINEAR            = 0x04
  FORMAT_FLAG_COLORMAP          = 0x08
  FORMAT_FLAG_BGR               = 0x10
  FORMAT_FLAG_AFIRST            = 0x20
  FORMAT_FLAG_ASSOCIATED_ALPHA  = 0x40

  FORMAT_GRAY = 0
  FORMAT_GA   = FORMAT_FLAG_ALPHA
  FORMAT_AG   = FORMAT_FLAG_ALPHA | FORMAT_FLAG_AFIRST
  FORMAT_RGB  = FORMAT_FLAG_COLOR
  FORMAT_BGR  = FORMAT_FLAG_COLOR | FORMAT_FLAG_BGR
  FORMAT_RGBA = FORMAT_FLAG_COLOR | FORMAT_FLAG_ALPHA
  FORMAT_ARGB = FORMAT_FLAG_COLOR | FORMAT_FLAG_ALPHA | FORMAT_FLAG_AFIRST
  FORMAT_BGRA = FORMAT_FLAG_COLOR | FORMAT_FLAG_ALPHA | FORMAT_FLAG_BGR
  FORMAT_ABGR = FORMAT_FLAG_COLOR | FORMAT_FLAG_ALPHA | FORMAT_FLAG_AFIRST | FORMAT_FLAG_BGR

  FORMAT_BY_NAME = {
    'GRAY' => FORMAT_GRAY,
    'GRAYSCALE' => FORMAT_GRAY,
    'GA' => FORMAT_GA,
    'AG' => FORMAT_AG,
    'RGB' => FORMAT_RGB,
    'BGR' => FORMAT_BGR,
    'RGBA' => FORMAT_RGBA,
    'ARGB' => FORMAT_ARGB,
    'BGRA' => FORMAT_BGRA,
    'ABGR' => FORMAT_ABGR
  }.freeze

  # ------------------------------------------------------------------
  # Standard-API color types (png.h).
  # ------------------------------------------------------------------
  COLOR_MASK_PALETTE = 0x01
  COLOR_MASK_COLOR   = 0x02
  COLOR_MASK_ALPHA   = 0x04

  COLOR_TYPE_GRAY         = 0
  COLOR_TYPE_PALETTE      = COLOR_MASK_COLOR | COLOR_MASK_PALETTE
  COLOR_TYPE_RGB          = COLOR_MASK_COLOR
  COLOR_TYPE_RGB_ALPHA    = COLOR_MASK_COLOR | COLOR_MASK_ALPHA
  COLOR_TYPE_GRAY_ALPHA   = COLOR_MASK_ALPHA

  FORMAT_TO_COLOR_TYPE = {
    gray: COLOR_TYPE_GRAY,
    ga: COLOR_TYPE_GRAY_ALPHA,
    ag: COLOR_TYPE_GRAY_ALPHA,
    rgb: COLOR_TYPE_RGB,
    rgba: COLOR_TYPE_RGB_ALPHA,
    palette: COLOR_TYPE_PALETTE
  }.freeze

  # ------------------------------------------------------------------
  # png_set_IHDR pass-through constants (png.h).
  # ------------------------------------------------------------------
  INTERLACE_NONE            = 0
  INTERLACE_ADAM7           = 1
  COMPRESSION_TYPE_DEFAULT  = 0
  FILTER_TYPE_DEFAULT       = 0
  TRANSFORM_IDENTITY        = 0x0000

  INTERLACE_BY_NAME = {
    none: INTERLACE_NONE,
    adam7: INTERLACE_ADAM7
  }.freeze

  # ------------------------------------------------------------------
  # png_set_filter bitmask (PNG_FILTER_*).
  # ------------------------------------------------------------------
  FILTER_HEURISTIC_DEFAULT  = 0
  FILTER_NONE               = 0x08
  FILTER_SUB                = 0x10
  FILTER_UP                 = 0x20
  FILTER_AVG                = 0x40
  FILTER_PAETH              = 0x80
  FILTER_ALL                = FILTER_NONE | FILTER_SUB | FILTER_UP | FILTER_AVG | FILTER_PAETH

  FILTER_MASK_BY_NAME = {
    default: nil,
    adaptive: FILTER_ALL,
    none: FILTER_NONE,
    sub: FILTER_SUB,
    up: FILTER_UP,
    avg: FILTER_AVG,
    paeth: FILTER_PAETH,
    all: FILTER_ALL
  }.freeze

  # ------------------------------------------------------------------
  # PNG_TEXT_COMP_* (compression field of png_text struct).
  # Used by the write path to choose tEXt / zTXt / iTXt output.
  # libpng's own constants are PNG_TEXT_COMPRESSION_{NONE,zTXt,iTXt}_KEY;
  # we use SCREAMING_SNAKE_CASE per Ruby convention.
  # ------------------------------------------------------------------
  TEXT_COMPRESSION_NONE      = -1 # tEXt
  TEXT_COMPRESSION_ZTXT_KEY  = 0  # zTXt (zlib)
  TEXT_COMPRESSION_ITXT_KEY  = 1  # iTXt (no compression by default)
  TEXT_COMPRESSION_LAST      = 2  # marker; not used as a real value

  TEXT_COMPRESSION_BY_NAME = {
    text: TEXT_COMPRESSION_NONE,
    ztxt: TEXT_COMPRESSION_ZTXT_KEY,
    itxt: TEXT_COMPRESSION_ITXT_KEY
  }.freeze

  # ------------------------------------------------------------------
  # sRGB rendering intents (png.h).
  # ------------------------------------------------------------------
  SRGB_INTENT_PERCEPTUAL            = 0
  SRGB_INTENT_RELATIVE_COLORIMETRIC = 1
  SRGB_INTENT_SATURATION            = 2
  SRGB_INTENT_ABSOLUTE              = 3

  # ------------------------------------------------------------------
  # pHYs unit types (png.h).
  # ------------------------------------------------------------------
  PHYS_TYPE_UNKNOWN = 0
  PHYS_TYPE_METER   = 1

  # Meters-per-inch (1 inch = 0.0254 m). Used to convert pHYs pixels-per-meter
  # to DPI: dpi = ppm * 0.0254.
  INCH_PER_METER = 0.0254

  # ------------------------------------------------------------------
  # PNG_INFO_* bit flags (png.h). Returned by png_get_valid to test
  # which chunks are present in an info_ptr. Renamed to SCREAMING_SNAKE
  # to match Ruby convention; libpng uses mixed case (PNG_INFO_tRNS,
  # PNG_INFO_bKGD, etc.) which doesn't pass Ruby style checks.
  # ------------------------------------------------------------------
  PNG_INFO_IHDR = 0x0001
  PNG_INFO_PLTE = 0x0002
  PNG_INFO_TRNS = 0x0004
  PNG_INFO_BKGD = 0x0008
  PNG_INFO_HIST = 0x0010
  PNG_INFO_PHYS = 0x0020
  PNG_INFO_OFFS = 0x0040
  PNG_INFO_TIME = 0x0080
  PNG_INFO_PCAL = 0x0100
  PNG_INFO_SRGB = 0x0200
  PNG_INFO_ICCP = 0x0400
  PNG_INFO_SBIT = 0x0800
  PNG_INFO_SPLT = 0x1000
  PNG_INFO_IDAT = 0x2000
  PNG_INFO_ACTL = 0x4000
  PNG_INFO_EXIF = 0x8000
  PNG_INFO_GAMA = 0x10000
  PNG_INFO_CHRM = 0x20000

  # png_set_rgb_to_gray error_action values.
  RGB_TO_GRAY_DEFAULT    = 1 # silent
  RGB_TO_GRAY_WARN       = 2 # warn on error
  RGB_TO_GRAY_ERR        = 3 # raise error

  # png_set_filler / png_set_add_alpha filler_position values.
  # Matches png.h: PNG_FILLER_BEFORE = 0, PNG_FILLER_AFTER = 1.
  FILLER_BEFORE = 0
  FILLER_AFTER = 1

  # PNG_LIBPNG_VER_STRING. The C string passed as `user_png_ver` to
  # png_create_write_struct. libpng checks this against its compiled-in
  # version; mismatches return NULL. Must match the libpng16 binary we
  # ship, which is 1.6.58.
  LIBPNG_VER_STRING_C = LIBPNG_VERSION

  # ------------------------------------------------------------------
  # png_image struct field offsets (bytes). Used by SimplifiedEncoder /
  # SimplifiedDecoder to allocate the png_image struct via a raw
  # FFI::MemoryPointer (rather than FFI::Struct, which has class-level
  # state that isn't shareable across non-main Ractors).
  # ------------------------------------------------------------------
  PNG_IMAGE_VERSION = 1
  PNG_IMAGE_MESSAGE_BYTES = 64
  PNG_IMAGE_SIZE = FFI.type_size(:pointer) + (7 * 4) + PNG_IMAGE_MESSAGE_BYTES
  PNG_IMAGE_OFF_OPAQUE = 0
  PNG_IMAGE_OFF_VERSION = FFI.type_size(:pointer)
  PNG_IMAGE_OFF_WIDTH = PNG_IMAGE_OFF_VERSION + 4
  PNG_IMAGE_OFF_HEIGHT = PNG_IMAGE_OFF_WIDTH + 4
  PNG_IMAGE_OFF_FORMAT = PNG_IMAGE_OFF_HEIGHT + 4
  PNG_IMAGE_OFF_FLAGS = PNG_IMAGE_OFF_FORMAT + 4
  PNG_IMAGE_OFF_COLORMAP_ENTRIES = PNG_IMAGE_OFF_FLAGS + 4
  PNG_IMAGE_OFF_WARNING_OR_ERROR = PNG_IMAGE_OFF_COLORMAP_ENTRIES + 4
  PNG_IMAGE_OFF_MESSAGE = PNG_IMAGE_OFF_WARNING_OR_ERROR + 4

  # ------------------------------------------------------------------
  # Public API. Each method constructs a dedicated encoder/decoder
  # instance, runs it, and returns its output. Keeping these as thin
  # dispatchers preserves the existing module-level API while letting
  # the heavy logic live in testable, single-purpose classes.
  # ------------------------------------------------------------------
  class << self
    # Encode raw pixels via the simplified API. Output is post-
    # processed to strip sRGB/gAMA/cHRM/iCCP chunks unless
    # strip_colorspace: false.
    def encode(width, height, pixels, **opts)
      SimplifiedEncoder.new(width, height, pixels, **opts).call
    end

    # Encode raw pixels via the standard write API. Accepts filter,
    # compression_level, interlace, bit_depth, and palette options,
    # plus text/gamma/srgb_intent/chromaticities/icc_profile/phys
    # metadata writers. Emits only the chunks libpng's standard path
    # produces (no post-hoc stripping needed).
    def encode_standard(width, height, pixels, **opts)
      StandardEncoder.new(width, height, pixels, **opts).call
    end

    # Decode a PNG buffer via libpng's simplified read API. Returns a
    # DecodedImage with width/height/format/pixels plus IHDR fields
    # and text/color/phys metadata (parsed via ChunkWalker).
    def decode(png, **opts)
      SimplifiedDecoder.new(png, **opts).call
    end

    # Decode a PNG buffer via libpng's standard read API
    # (png_create_read_struct -> png_read_info -> optional transforms
    # -> png_read_image). Use this instead of `decode` when you need
    # explicit control over which transforms apply. Returns a
    # DecodedImage with the same metadata fields as `decode`.
    def decode_standard(png, **opts)
      StandardDecoder.new(png, **opts).call
    end
  end
end
