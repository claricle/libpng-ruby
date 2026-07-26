# frozen_string_literal: true

module Libpng
  # Decodes a PNG byte buffer into raw pixels via libpng's "simplified"
  # read API (png_image_begin_read_from_memory + png_image_finish_read).
  #
  # Also parses the byte buffer via ChunkWalker to populate
  # DecodedImage#bit_depth, #color_type, #interlace (from IHDR),
  # #text (from tEXt/zTXt/iTXt), and #color (from gAMA/cHRM/sRGB/iCCP).
  # The simplified API itself drops these ancillary chunks on read --
  # walking them separately is the only way to surface their content.
  #
  # One instance per decode call. Ractor-safe.
  class SimplifiedDecoder
    def initialize(png, pixel_format: 'RGBA')
      raise Error, 'input PNG buffer is nil' if png.nil?
      raise Error, 'input PNG buffer must be a String' unless png.is_a?(String)

      @png = png
      @pixel_format = pixel_format
      raise Error, "unknown pixel_format #{@pixel_format.inspect}" unless format_value
    end

    # Returns a Libpng::DecodedImage.
    def call
      fmt = format_value
      img = FFI::MemoryPointer.new(:uint8, PNG_IMAGE_SIZE)
      img.clear
      img.put_uint32(PNG_IMAGE_OFF_VERSION, PNG_IMAGE_VERSION)

      FFI::MemoryPointer.new(:uint8, @png.bytesize) do |in_buf|
        in_buf.write_bytes(@png)
        ok = Libpng::Binding.png_image_begin_read_from_memory(img, in_buf, @png.bytesize)
        raise Error, "png_image_begin_read_from_memory failed: #{read_message(img)}" if ok.zero?

        img.put_uint32(PNG_IMAGE_OFF_FORMAT, fmt)
        width = img.get_uint32(PNG_IMAGE_OFF_WIDTH)
        height = img.get_uint32(PNG_IMAGE_OFF_HEIGHT)
        stride = width * BytesPerPixel.for_format(fmt)
        out_size = stride * height

        FFI::MemoryPointer.new(:uint8, out_size) do |out_buf|
          ok = Libpng::Binding.png_image_finish_read(img, nil, out_buf, stride, nil)
          raise Error, "png_image_finish_read failed: #{read_message(img)}" if ok.zero?

          return DecodedImage.new(
            width: width,
            height: height,
            format: @pixel_format.to_s.upcase,
            pixels: out_buf.read_bytes(out_size),
            **walker_metadata
          )
        end
      end
    ensure
      Libpng::Binding.png_image_free(img) unless img.nil? || img.null?
    end

    private

    def format_value
      FORMAT_BY_NAME[@pixel_format.to_s.upcase]
    end

    # Walks the PNG once via ChunkWalker to gather all metadata fields
    # the simplified API does not surface. Each accessor is best-effort:
    # a malformed IHDR or text chunk should not poison the rest of the
    # decode -- empty Hashes / nil values are acceptable fall-throughs.
    def walker_metadata
      walker = ChunkWalker.new(@png)
      ihdr = safe_ihdr(walker)
      {
        bit_depth: ihdr[:bit_depth],
        color_type: ihdr[:color_type],
        interlace: ihdr[:interlace],
        text: safe_text(walker),
        color: safe_color(walker),
        phys: safe_phys(walker)
      }
    end

    def safe_ihdr(walker)
      walker.ihdr_fields
    rescue ChunkWalker::FormatError
      {}
    end

    def safe_text(walker)
      walker.text_chunks
    rescue ChunkWalker::FormatError
      {}
    end

    def safe_color(walker)
      walker.color_chunks
    rescue ChunkWalker::FormatError
      {}
    end

    def safe_phys(walker)
      walker.phys_chunk
    rescue ChunkWalker::FormatError
      nil
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
