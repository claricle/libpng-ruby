# frozen_string_literal: true

module Libpng
  # Encodes raw pixel data as a PNG via libpng's "simplified" write API
  # (png_image_write_to_memory). By default the output is then walked
  # chunk-by-chunk to strip the sRGB/gAMA/cHRM/iCCP chunks the
  # simplified API emits -- this matches the byte layout of the
  # classic libpng write path (libemf2svg's rgb2png).
  #
  # One instance per encode call. Ractor-safe: no shared mutable state.
  class SimplifiedEncoder
    def initialize(width, height, pixels,
                   pixel_format: 'RGBA',
                   convert_to_8bit: false,
                   strip_colorspace: true)
      @width = width
      @height = height
      @pixels = pixels
      @pixel_format = pixel_format
      @convert_to_8bit = convert_to_8bit
      @strip_colorspace = strip_colorspace
      validate!
    end

    # Returns a binary String of PNG file bytes.
    def call
      raw = write_via_simplified_api
      @strip_colorspace ? ChunkWalker.new(raw).strip_ancillary : raw
    end

    private

    def validate!
      raise Error, 'width must be positive' unless @width.positive?
      raise Error, 'height must be positive' unless @height.positive?
      raise Error, "unknown pixel_format #{@pixel_format.inspect}" unless format_value
      return unless @pixels.bytesize < expected_size

      raise Error,
            "pixels too short: expected #{expected_size}, got #{@pixels.bytesize}"
    end

    def format_value
      FORMAT_BY_NAME[@pixel_format.to_s.upcase]
    end

    def bytes_per_pixel
      BytesPerPixel.for_format(format_value)
    end

    def expected_size
      @width * bytes_per_pixel * @height
    end

    def write_via_simplified_api
      img = FFI::MemoryPointer.new(:uint8, PNG_IMAGE_SIZE)
      img.clear
      img.put_uint32(PNG_IMAGE_OFF_VERSION, PNG_IMAGE_VERSION)
      img.put_uint32(PNG_IMAGE_OFF_WIDTH, @width)
      img.put_uint32(PNG_IMAGE_OFF_HEIGHT, @height)
      img.put_uint32(PNG_IMAGE_OFF_FORMAT, format_value)

      stride = @width * bytes_per_pixel
      out_len_ptr = FFI::MemoryPointer.new(:size_t, 1)
      ok = Libpng::Binding.png_image_write_to_memory(img, nil, out_len_ptr,
                                                     @convert_to_8bit ? 1 : 0,
                                                     @pixels, stride, nil)
      if ok.zero?
        msg = read_message(img)
        Libpng::Binding.png_image_free(img)
        raise Error, "png_image_write_to_memory (size query) failed: #{msg}"
      end

      out_len = out_len_ptr.read_uint64
      raise Error, 'libpng reported zero-length PNG output' if out_len.zero?

      buffer = FFI::MemoryPointer.new(:uint8, out_len)
      ok = Libpng::Binding.png_image_write_to_memory(img, buffer, out_len_ptr,
                                                     @convert_to_8bit ? 1 : 0,
                                                     @pixels, stride, nil)
      if ok.zero?
        msg = read_message(img)
        Libpng::Binding.png_image_free(img)
        raise Error, "png_image_write_to_memory (write) failed: #{msg}"
      end

      buffer.read_bytes(out_len).tap { Libpng::Binding.png_image_free(img) }
    end

    def read_message(img)
      s = img.get_bytes(PNG_IMAGE_OFF_MESSAGE, PNG_IMAGE_MESSAGE_BYTES)
      s = s.split("\x00").first || ''
      s.empty? ? '(no message)' : s.force_encoding('UTF-8')
    rescue StandardError
      '(no message)'
    end
  end
end
