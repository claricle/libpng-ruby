# frozen_string_literal: true

require 'ffi'
require 'zlib'

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
# different Ractors do not share state. The module's FFI function table
# is set up once at load time and is shareable across Ractors.
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

  # Build-time recipe (MiniPortile). Only loaded when ext/extconf.rb
  # is invoked during `gem install` of the source ('ruby' platform) gem.
  autoload :Recipe, 'libpng/recipe'

  extend FFI::Library

  ffi_lib_flags :now, :global

  lib_filename = if FFI::Platform.windows?
                   'libpng16.dll'
                 elsif FFI::Platform.mac?
                   'libpng16.dylib'
                 else
                   'libpng16.so'
                 end

  ffi_lib File.expand_path("libpng/#{lib_filename}", __dir__)
              .gsub('/', File::ALT_SEPARATOR || File::SEPARATOR)

  # libpng simplified API (png_image / png_image_*). All return int
  # (1 on success, 0 on failure); the png_image's message buffer holds
  # the error string on failure.
  attach_function :png_image_begin_read_from_memory,
                  %i[pointer pointer size_t], :int
  attach_function :png_image_finish_read,
                  %i[pointer pointer pointer int pointer], :int
  attach_function :png_image_write_to_memory,
                  %i[pointer pointer pointer int pointer int pointer], :int
  attach_function :png_image_free, [:pointer], :void

  # libpng standard (non-simplified) write API. Used by StandardEncoder.
  attach_function :png_create_write_struct,
                  %i[string pointer pointer pointer], :pointer
  attach_function :png_create_info_struct, [:pointer], :pointer
  attach_function :png_destroy_write_struct, %i[pointer pointer], :void
  attach_function :png_set_IHDR,
                  %i[pointer pointer uint32 uint32 int int int int int], :void
  attach_function :png_set_rows, %i[pointer pointer pointer], :void
  attach_function :png_set_PLTE, %i[pointer pointer pointer int], :void
  attach_function :png_set_tRNS,
                  %i[pointer pointer pointer int pointer], :void
  attach_function :png_set_filter, %i[pointer int int], :void
  attach_function :png_set_compression_level, %i[pointer int], :void
  attach_function :png_set_write_fn,
                  %i[pointer pointer pointer pointer], :void
  attach_function :png_write_png, %i[pointer pointer int pointer], :void

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

  # Symbolic names accepted by StandardEncoder. Symbol keys so callers
  # can pass `pixel_format: :palette` or `'RGBA'` interchangeably.
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
  #
  # Note: :default means "don't call png_set_filter at all" -- libpng
  # uses its built-in adaptive filtering (all filters considered,
  # minimum-sum-of-absolute-differences per row). :adaptive and :all
  # explicitly call png_set_filter with FILTER_ALL; the output is
  # byte-identical to :default in practice but exercises a different
  # code path inside libpng. :none forces PNG_FILTER_NONE only, which
  # usually produces a larger IDAT for non-trivial images.
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

  # PNG_LIBPNG_VER_STRING. The C string passed as `user_png_ver` to
  # png_create_write_struct. libpng checks this against its compiled-in
  # version; mismatches return NULL. Must match the libpng16 binary we
  # ship, which is 1.6.58. LIBPNG_VERSION is the autoloaded constant
  # from lib/libpng/version.rb (frozen string literal).
  LIBPNG_VER_STRING_C = LIBPNG_VERSION

  # ------------------------------------------------------------------
  # png_image struct field offsets (bytes). png_image is laid out as:
  #   void*       opaque             (pointer-width)
  #   png_uint_32 version            (uint32)
  #   png_uint_32 width              (uint32)
  #   png_uint_32 height             (uint32)
  #   png_uint_32 format             (uint32)
  #   png_uint_32 flags              (uint32)
  #   png_uint_32 colormap_entries   (uint32)
  #   png_uint_32 warning_or_error   (uint32)
  #   char[64]    message
  # The fixed width makes it safe to allocate via FFI::MemoryPointer
  # directly so the wrapper stays Ractor-safe (FFI::Struct has class-
  # level state that isn't shareable across non-main Ractors).
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
    # compression_level, interlace, bit_depth, and palette options.
    # Emits only IHDR/IDAT/IEND directly (no chunk stripping needed).
    def encode_standard(width, height, pixels, **opts)
      StandardEncoder.new(width, height, pixels, **opts).call
    end

    # Decode a PNG buffer into raw pixels plus IHDR metadata.
    def decode(png, **opts)
      SimplifiedDecoder.new(png, **opts).call
    end
  end
end
