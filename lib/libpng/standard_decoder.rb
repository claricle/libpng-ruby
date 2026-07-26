# frozen_string_literal: true

module Libpng
  # Decodes a PNG byte buffer into raw pixels via libpng's standard
  # read API (png_create_read_struct -> png_set_read_fn -> png_read_info
  # -> optional transforms -> png_read_image). This is the read-side
  # counterpart to StandardEncoder; together they expose libpng's full
  # low-level read/write surface, complementing the simplified API.
  #
  # Why use this instead of Libpng.decode (the simplified path)?
  # - Explicit control over which transforms apply (the simplified
  #   API auto-applies a fixed set).
  # - Useful when the caller wants to inspect the source pixel format
  #   before deciding how to expand it (e.g. skip palette expansion
  #   for performance on already-RGBA images).
  #
  # Options:
  #   pixel_format:     The desired output format. One of:
  #                     :gray, :ga, :rgb, :rgba (default).
  #                     Determines which expansion / stripping
  #                     transforms get applied.
  #   bit_depth:        8 (default) or 16. 16-bit output preserves
  #                     the source's full range when the source is
  #                     also 16-bit; otherwise the source is
  #                     promoted (8 -> 16 by zero-extension) or
  #                     demoted (16 -> 8 by png_set_strip_16).
  #
  # Output:
  #   Returns a Libpng::DecodedImage. The :text, :color, :phys
  #   metadata fields are populated via ChunkWalker (same as the
  #   simplified path) so callers get the same metadata story
  #   regardless of which decode path they use.
  #
  # One instance per decode call. Ractor-safe.
  class StandardDecoder
    # Read-state accumulator. The libpng read callback reads PNG bytes
    # out of this; the offset advances with each call. Wrapping the
    # state in a small struct keeps the FFI::Function closure capture
    # explicit (and the closure itself becomes trivially shareable
    # because the struct's instance vars are not mutated outside the
    # callback).
    ReadState = Struct.new(:bytes, :offset, keyword_init: true)

    # PNG file signature: 8 bytes.
    SIGNATURE_BYTES = [137, 80, 78, 71, 13, 10, 26, 10].freeze

    def initialize(png, pixel_format: 'RGBA', bit_depth: 8)
      raise Error, 'input PNG buffer is nil' if png.nil?
      raise Error, 'input PNG buffer must be a String' unless png.is_a?(String)
      raise Error, 'input is too short to be a PNG' if png.bytesize < 8
      raise Error, 'input is not a PNG (bad signature)' unless png.bytes.first(8) == SIGNATURE_BYTES

      @png = png
      @pixel_format_sym = coerce_pixel_format(pixel_format)
      @target_bit_depth = bit_depth
      raise Error, 'bit_depth must be 8 or 16' unless [8, 16].include?(@target_bit_depth)
    end

    # Returns a Libpng::DecodedImage.
    def call
      output = String.new.force_encoding('ASCII-8BIT')
      state = ReadState.new(bytes: @png, offset: 0)
      read_fn = make_read_fn(state)
      error_fn = make_error_fn

      png_ptr = FFI::Pointer.new(0)
      info_ptr = FFI::Pointer.new(0)
      begin
        png_ptr = Libpng::Binding.png_create_read_struct(LIBPNG_VER_STRING_C, nil, error_fn, nil)
        raise Error, 'png_create_read_struct returned NULL' if png_ptr.null?

        info_ptr = Libpng::Binding.png_create_info_struct(png_ptr)
        raise Error, 'png_create_info_struct returned NULL' if info_ptr.null?

        # Read callback + flush (NULL); we read from memory, not a file.
        Libpng::Binding.png_set_read_fn(png_ptr, nil, read_fn, nil)

        Libpng::Binding.png_read_info(png_ptr, info_ptr)
        width = Libpng::Binding.png_get_image_width(png_ptr, info_ptr)
        height = Libpng::Binding.png_get_image_height(png_ptr, info_ptr)
        src_bit_depth = Libpng::Binding.png_get_bit_depth(png_ptr, info_ptr)
        src_color_type = Libpng::Binding.png_get_color_type(png_ptr, info_ptr)

        apply_transforms(png_ptr, info_ptr, src_bit_depth, src_color_type)
        # png_set_interlace_handling returns the pass count (1 for
        # non-interlaced, 7 for Adam7). png_read_image handles the
        # multi-pass accumulation automatically once this is set.
        Libpng::Binding.png_set_interlace_handling(png_ptr)
        Libpng::Binding.png_read_update_info(png_ptr, info_ptr)

        row_bytes = Libpng::Binding.png_get_rowbytes(png_ptr, info_ptr)
        out_size = row_bytes * height

        FFI::MemoryPointer.new(:uint8, out_size) do |out_buf|
          FFI::MemoryPointer.new(:pointer, height) do |rows|
            height.times do |y|
              rows.put_pointer(y * FFI.type_size(:pointer), out_buf + (y * row_bytes))
            end
            Libpng::Binding.png_read_image(png_ptr, rows)
          end
          output << out_buf.read_bytes(out_size)
        end

        Libpng::Binding.png_read_end(png_ptr, info_ptr)

        metadata = walker_metadata
        DecodedImage.new(
          width: width,
          height: height,
          format: @pixel_format_sym.upcase.to_s,
          pixels: output,
          bit_depth: metadata[:bit_depth],
          color_type: metadata[:color_type],
          interlace: metadata[:interlace],
          text: metadata[:text],
          color: metadata[:color],
          phys: metadata[:phys]
        )
      ensure
        destroy(png_ptr, info_ptr)
      end
    end

    private

    def coerce_pixel_format(value)
      sym = value.to_s.downcase.to_sym
      raise Error, "unknown pixel_format #{value.inspect}" unless FORMAT_TO_COLOR_TYPE.key?(sym)
      raise Error, 'pixel_format :palette is write-only' if sym == :palette

      sym
    end

    # Apply libpng transforms based on the requested output format and
    # the source's actual color type / bit depth. The ordering matters
    # -- libpng documents the canonical sequence in libpng-manual.txt
    # section "Reading PNG files step-by-step".
    def apply_transforms(png_ptr, info_ptr, src_bit_depth, src_color_type)
      # 1. Expand everything to 8-bit first (sub-8 gray + palette).
      if src_bit_depth < 8
        Libpng::Binding.png_set_expand(png_ptr)
      elsif src_bit_depth == 16 && @target_bit_depth == 8
        Libpng::Binding.png_set_strip_16(png_ptr)
      end

      target_color_type = FORMAT_TO_COLOR_TYPE[@pixel_format_sym]
      src_has_alpha = src_color_type.anybits?(COLOR_MASK_ALPHA)
      src_has_color = src_color_type.anybits?(COLOR_MASK_COLOR)
      target_has_alpha = target_color_type.anybits?(COLOR_MASK_ALPHA)
      target_has_color = target_color_type.anybits?(COLOR_MASK_COLOR)

      # 2. Palette -> RGB (always; we don't expose palette output).
      Libpng::Binding.png_set_palette_to_rgb(png_ptr) if src_color_type == COLOR_TYPE_PALETTE

      # 3. tRNS -> explicit alpha (only meaningful when caller wants alpha).
      if target_has_alpha && png_get_valid(png_ptr, info_ptr, PNG_INFO_TRNS).positive?
        Libpng::Binding.png_set_tRNS_to_alpha(png_ptr)
      end

      # 4. Gray <-> RGB conversion.
      if !src_has_color && target_has_color
        Libpng::Binding.png_set_gray_to_rgb(png_ptr)
      elsif src_has_color && !target_has_color
        Libpng::Binding.png_set_rgb_to_gray(png_ptr, RGB_TO_GRAY_DEFAULT, -1.0, -1.0)
      end

      # 5. Add / strip alpha to match target.
      if target_has_alpha && !src_has_alpha
        # Add a fully-opaque alpha channel after the RGB bytes.
        Libpng::Binding.png_set_add_alpha(png_ptr, 0xFF, FILLER_AFTER)
      elsif !target_has_alpha && src_has_alpha
        Libpng::Binding.png_set_strip_alpha(png_ptr)
      end
    end

    def png_get_valid(png_ptr, info_ptr, flag)
      Libpng::Binding.png_get_valid(png_ptr, info_ptr, flag)
    end

    def make_read_fn(state)
      # Closure captures `state`. Reads up to `len` bytes into `dst`,
      # starting from the current offset and advancing it.
      FFI::Function.new(:void, %i[pointer pointer size_t]) do |_png_ptr, dst, len|
        avail = state.bytes.bytesize - state.offset
        n = [len, avail].min
        if n.positive?
          dst.write_bytes(state.bytes.byteslice(state.offset, n), 0, n)
          state.offset += n
        end
        # If the caller asked for more than we have, libpng treats it as
        # an error (premature EOF) and longjmps out via the error handler.
      end
    end

    # libpng's standard error path uses setjmp/longjmp. We install an
    # error_fn that raises a Ruby exception instead -- the raise itself
    # unwinds the C stack via FFI's safety mechanisms (rb_protect-style).
    def make_error_fn
      FFI::Function.new(:void, %i[pointer string]) do |_png_ptr, msg|
        raise Error, "libpng: #{msg}"
      end
    end

    def walker_metadata
      walker = ChunkWalker.new(@png)
      ihdr = walker.ihdr_fields
      {
        bit_depth: ihdr[:bit_depth],
        color_type: ihdr[:color_type],
        interlace: ihdr[:interlace],
        text: walker.text_chunks,
        color: walker.color_chunks,
        phys: walker.phys_chunk
      }
    rescue ChunkWalker::FormatError
      {
        bit_depth: nil, color_type: nil, interlace: nil,
        text: {}, color: {}, phys: nil
      }
    end

    def destroy(png_ptr, info_ptr)
      return if png_ptr.null?

      FFI::MemoryPointer.new(:pointer) do |pp|
        pp.write_pointer(png_ptr)
        FFI::MemoryPointer.new(:pointer) do |ip|
          ip.write_pointer(info_ptr)
          Libpng::Binding.png_destroy_read_struct(pp, ip, nil)
        end
      end
    end
  end
end
