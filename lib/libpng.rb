# frozen_string_literal: true

require 'ffi'
require 'zlib'
require_relative 'libpng/version'

# Libpng is a Ruby binding for libpng (the official PNG reference library)
# via FFI. The native library is pre-compiled for each target platform and
# shipped inside the gem, so no C compiler is required at install time.
#
# The API mirrors libpng's "simplified" high-level API:
#
#   Libpng.encode(width, height, rgba_bytes, pixel_format: "RGBA")
#   Libpng.decode(png_bytes, pixel_format: "RGBA")
#
# All encode/decode state is per-call (libpng allocates and frees a
# png_image internally), so calls from different Ractors do not share
# state. The module's FFI function table is frozen at load time.
module Libpng
  class Error < StandardError; end

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

  # PNG_IMAGE_FORMAT_* bit flags and named formats from png.h.
  FORMAT_FLAG_ALPHA = 0x01
  FORMAT_FLAG_COLOR = 0x02
  FORMAT_FLAG_LINEAR = 0x04
  FORMAT_FLAG_COLORMAP = 0x08
  FORMAT_FLAG_BGR = 0x10
  FORMAT_FLAG_AFIRST = 0x20
  FORMAT_FLAG_ASSOCIATED_ALPHA = 0x40

  FORMAT_GRAY = 0
  FORMAT_GA = FORMAT_FLAG_ALPHA
  FORMAT_AG = FORMAT_FLAG_ALPHA | FORMAT_FLAG_AFIRST
  FORMAT_RGB = FORMAT_FLAG_COLOR
  FORMAT_BGR = FORMAT_FLAG_COLOR | FORMAT_FLAG_BGR
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

  # png_image::version value libpng checks for. Defined in png.h as
  # PNG_IMAGE_VERSION == 1.
  PNG_IMAGE_VERSION = 1

  # Buffer size for libpng's per-image error message (PNG_IMAGE_MESSAGE_BYTES).
  # The png_image struct stores a fixed-size char buffer of this length.
  PNG_IMAGE_MESSAGE_BYTES = 64

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
  # Total = pointer-size + 7*4 + 64. The fixed width makes it safe to
  # allocate via FFI::MemoryPointer directly so the wrapper stays
  # Ractor-safe (FFI::Struct has class-level state that isn't shareable
  # across non-main Ractors).
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

  # Result struct for Libpng.decode (returned as a plain Hash for simplicity).
  DecodedImage = Struct.new(:width, :height, :format, :pixels, keyword_init: true)

  class << self
    # Encode raw pixel data as a PNG.
    #
    # +width+, +height+    image dimensions in pixels
    # +pixels+             String of raw pixel bytes (row-major, top-down)
    # +pixel_format+       "RGB", "RGBA", "GRAY", "GA", "BGR", "BGRA"
    #                      (default: "RGBA")
    # +convert_to_8bit+    when true, libpng converts 16-bit input to 8-bit
    #                      on write (default: false)
    # +strip_colorspace+   when true, removes any sRGB/gAMA/cHRM/iCCP chunks
    #                      libpng's simplified API emits by default, leaving
    #                      only IHDR, IDAT, and IEND. This matches the
    #                      "classic" libpng write path (e.g. libemf2svg) and
    #                      produces byte-identical output. Default: true.
    #
    # Returns a String containing the PNG file bytes. Raises Libpng::Error
    # on failure (bad dimensions, insufficient input bytes, invalid
    # pixel_format, or libpng-internal error).
    #
    # Ractor-safe: every call allocates and frees its own png_image; no
    # shared mutable state.
    def encode(width, height, pixels, pixel_format: 'RGBA',
               convert_to_8bit: false, strip_colorspace: true)
      raw = encode_ancillary(width, height, pixels,
                             pixel_format: pixel_format,
                             convert_to_8bit: convert_to_8bit)
      strip_colorspace ? strip_ancillary_chunks(raw) : raw
    end

    # Decode a PNG file into raw pixels.
    #
    # +png+           String containing PNG file bytes
    # +pixel_format+  desired output format ("RGB", "RGBA", "GRAY", etc.)
    #                 (default: "RGBA")
    #
    # Returns a DecodedImage Struct with #width, #height, #format (String),
    # and #pixels (binary String).
    #
    # Ractor-safe: same reason as encode.
    def decode(png, pixel_format: 'RGBA')
      fmt = FORMAT_BY_NAME[pixel_format.to_s.upcase] ||
            raise(Error, "unknown pixel_format #{pixel_format.inspect}")

      img = FFI::MemoryPointer.new(:uint8, PNG_IMAGE_SIZE)
      img.clear
      img.put_uint32(PNG_IMAGE_OFF_VERSION, PNG_IMAGE_VERSION)

      begin
        FFI::MemoryPointer.new(:uint8, png.bytesize) do |in_buf|
          in_buf.write_bytes(png)
          ok = png_image_begin_read_from_memory(img, in_buf, png.bytesize)
          if ok.zero?
            msg = read_message(img)
            raise Error, "png_image_begin_read_from_memory failed: #{msg}"
          end

          img.put_uint32(PNG_IMAGE_OFF_FORMAT, fmt)
          width = img.get_uint32(PNG_IMAGE_OFF_WIDTH)
          height = img.get_uint32(PNG_IMAGE_OFF_HEIGHT)
          stride = width * bytes_per_pixel_for_format(fmt)
          out_size = stride * height

          FFI::MemoryPointer.new(:uint8, out_size) do |out_buf|
            ok = png_image_finish_read(img, nil, out_buf, stride, nil)
            if ok.zero?
              msg = read_message(img)
              raise Error, "png_image_finish_read failed: #{msg}"
            end
            return DecodedImage.new(width: width,
                                    height: height,
                                    format: pixel_format.to_s.upcase,
                                    pixels: out_buf.read_bytes(out_size))
          end
        end
      ensure
        png_image_free(img)
      end
    end

    private

    # Lower-level encode that produces the raw libpng output (with sRGB
    # or gAMA chunks depending on libpng's defaults). Public #encode strips
    # these by default to match the classic libpng write path.
    def encode_ancillary(width, height, pixels, pixel_format:, convert_to_8bit:)
      raise Error, 'width must be positive' unless width.positive?
      raise Error, 'height must be positive' unless height.positive?

      fmt = FORMAT_BY_NAME[pixel_format.to_s.upcase] ||
            raise(Error, "unknown pixel_format #{pixel_format.inspect}")

      bytes_per_pixel = bytes_per_pixel_for_format(fmt)
      stride = width * bytes_per_pixel
      expected = stride * height
      raise Error, "pixels too short: expected #{expected}, got #{pixels.bytesize}" if pixels.bytesize < expected

      img = FFI::MemoryPointer.new(:uint8, PNG_IMAGE_SIZE)
      img.clear
      img.put_uint32(PNG_IMAGE_OFF_VERSION, PNG_IMAGE_VERSION)
      img.put_uint32(PNG_IMAGE_OFF_WIDTH, width)
      img.put_uint32(PNG_IMAGE_OFF_HEIGHT, height)
      img.put_uint32(PNG_IMAGE_OFF_FORMAT, fmt)

      out_len_ptr = FFI::MemoryPointer.new(:size_t, 1)
      ok = png_image_write_to_memory(img, nil, out_len_ptr,
                                     convert_to_8bit ? 1 : 0,
                                     pixels, stride, nil)
      if ok.zero?
        msg = read_message(img)
        png_image_free(img)
        raise Error, "png_image_write_to_memory (size query) failed: #{msg}"
      end

      out_len = out_len_ptr.read_uint64
      raise Error, 'libpng reported zero-length PNG output' if out_len.zero?

      buffer = FFI::MemoryPointer.new(:uint8, out_len)
      ok = png_image_write_to_memory(img, buffer, out_len_ptr,
                                     convert_to_8bit ? 1 : 0,
                                     pixels, stride, nil)
      if ok.zero?
        msg = read_message(img)
        png_image_free(img)
        raise Error, "png_image_write_to_memory (write) failed: #{msg}"
      end

      result = buffer.read_bytes(out_len)
      png_image_free(img)
      result
    end

    # Walk the PNG chunk list, keeping only IHDR, IDAT, and IEND. The PNG
    # signature (8 bytes) is preserved. We do NOT need to recompute CRCs —
    # the simplified API's emitted chunks (including the ones we drop) are
    # all correctly CRCd; we only need to walk the chunk list and keep the
    # ones we want, byte-for-byte.
    def strip_ancillary_chunks(png_bytes)
      sig = png_bytes.bytes[0, 8]
      raise Error, 'not a PNG file (bad signature)' unless sig == [137, 80, 78, 71, 13, 10, 26, 10]

      kept = sig.pack('C*')
      offset = 8
      while offset + 8 <= png_bytes.bytesize
        len = png_bytes.bytes[offset, 4].pack('C*').unpack1('N')
        type = png_bytes.bytes[offset + 4, 4].pack('C*')
        chunk_total = 12 + len
        raise Error, "PNG chunk at offset #{offset} runs past EOF" if offset + chunk_total > png_bytes.bytesize

        crc_input = png_bytes.bytes[offset + 4, 4 + len].pack('C*')
        crc_actual = png_bytes.bytes[offset + 8 + len, 4].pack('C*').unpack1('N')
        crc_expected = Zlib.crc32(crc_input)
        raise Error, "PNG chunk CRC mismatch at offset #{offset} (#{type})" unless crc_actual == crc_expected

        kept << png_bytes.bytes[offset, chunk_total].pack('C*') if %w[IHDR IDAT IEND].include?(type)
        offset += chunk_total
        break if type == 'IEND'
      end
      kept.force_encoding('ASCII-8BIT')
    end

    def read_message(img)
      # img[:message] is an Array field (char[64]); FFI returns a
      # CharArray, which doesn't respond to .null? but does support to_ptr
      # and to_s.

      s = img[:message].to_s
      s.empty? ? '(no message)' : s.force_encoding('UTF-8')
    rescue StandardError
      '(no message)'
    end

    def bytes_per_pixel_for_format(fmt)
      case fmt
      when FORMAT_GRAY then 1
      when FORMAT_GA, FORMAT_AG then 2
      when FORMAT_RGB, FORMAT_BGR then 3
      when FORMAT_RGBA, FORMAT_ARGB, FORMAT_BGRA, FORMAT_ABGR then 4
      else raise Error, "no bytes-per-pixel mapping for format 0x#{fmt.to_s(16)}"
      end
    end
  end
end
