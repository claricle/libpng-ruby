# frozen_string_literal: true

module Libpng
  # Encodes raw pixel data via libpng's standard write API
  # (png_create_write_struct -> png_set_IHDR -> png_set_rows ->
  # png_write_png(PNG_TRANSFORM_IDENTITY)). This matches the byte
  # output of the "classic" libpng write path used by libemf2svg's
  # rgb2png, and avoids the sRGB/gAMA chunks the simplified API
  # injects by default.
  #
  # Options:
  #   pixel_format:     :gray, :ga, :rgb, :rgba, or :palette
  #   filter:           :default (adaptive), :none, :sub, :up, :avg,
  #                     :paeth, :all, :adaptive
  #   compression_level: 0..9 (default 6 = Z_DEFAULT_COMPRESSION)
  #   interlace:        :none or :adam7 (default :none)
  #   bit_depth:        8 or 16 (default 8; ignored for :palette which
  #                     is always 8)
  #   palette:          Array of [r, g, b] or [r, g, b, a] for
  #                     pixel_format: :palette. 1..256 entries.
  #
  # Metadata options (forwarded to MetadataWriter; written between
  # IHDR/PLTE and png_write_png):
  #   text:             Hash<String,String> of tEXt keyword -> value.
  #                     Values with non-ASCII bytes use iTXt (UTF-8).
  #   gamma:            Float file gamma (e.g. 0.45455 for sRGB).
  #   srgb_intent:      Integer 0..3 (perceptual, relative-colorimetric,
  #                     saturation, absolute-colorimetric).
  #   chromaticities:   Hash with :white_point_x/y, :red_x/y,
  #                     :green_x/y, :blue_x/y (each a Float 0..1).
  #   icc_profile:      Hash with :name (String) and :data (binary
  #                     String). libpng compresses via zlib internally.
  #   phys:             Hash with :pixels_per_unit_x, :pixels_per_unit_y,
  #                     and :unit (0 = unknown, 1 = meters).
  #
  # One instance per encode call. Ractor-safe.
  class StandardEncoder
    METADATA_KEYS = %i[text gamma srgb_intent chromaticities icc_profile phys].freeze

    def initialize(width, height, pixels,
                   pixel_format: 'RGBA',
                   filter: :default,
                   compression_level: 6,
                   interlace: :none,
                   bit_depth: 8,
                   palette: nil,
                   **metadata)
      @width = width
      @height = height
      @pixels = pixels
      @pixel_format_sym = coerce_pixel_format(pixel_format)
      @filter_sym = filter.to_sym
      @compression_level = compression_level
      @interlace_sym = interlace.to_sym
      @bit_depth = bit_depth
      @palette = palette
      @metadata = metadata
      validate!
    end

    # Returns a binary String of PNG file bytes.
    def call
      output = String.new.force_encoding('ASCII-8BIT')
      callbacks = CallbackSet.new(output)

      png_ptr = FFI::Pointer.new(0)
      info_ptr = FFI::Pointer.new(0)
      begin
        png_ptr = Libpng::Binding.png_create_write_struct(LIBPNG_VER_STRING_C, nil, callbacks.error_fn, nil)
        raise Error, 'png_create_write_struct returned NULL' if png_ptr.null?

        info_ptr = Libpng::Binding.png_create_info_struct(png_ptr)
        raise Error, 'png_create_info_struct returned NULL' if info_ptr.null?

        apply_compression(png_ptr)
        Libpng::Binding.png_set_write_fn(png_ptr, nil, callbacks.write_fn, nil)
        Libpng::Binding.png_set_IHDR(png_ptr, info_ptr, @width, @height, effective_bit_depth,
                                     color_type, interlace_method,
                                     COMPRESSION_TYPE_DEFAULT, FILTER_TYPE_DEFAULT)
        apply_filter(png_ptr)
        apply_palette(png_ptr, info_ptr) if palette_format?
        # Metadata writers run AFTER IHDR/PLTE and BEFORE png_write_png
        # (which is what calls png_write_info -> emits all queued chunks).
        MetadataWriter.apply(png_ptr, info_ptr, @metadata)

        FFI::MemoryPointer.new(:uint8, @pixels.bytesize) do |px|
          px.write_bytes(@pixels)
          FFI::MemoryPointer.new(:pointer, @height) do |rows|
            @height.times do |y|
              rows.put_pointer(y * FFI.type_size(:pointer), px + (y * stride))
            end
            Libpng::Binding.png_set_rows(png_ptr, info_ptr, rows)
            Libpng::Binding.png_write_png(png_ptr, info_ptr, TRANSFORM_IDENTITY, nil)
          end
        end

        output
      ensure
        destroy(png_ptr, info_ptr)
      end
    end

    private

    # Holds FFI::Function callbacks alive for the duration of the
    # libpng calls. FFI::Function objects are GC'd when no Ruby
    # reference remains; libpng stores the raw function pointer but
    # has no idea the underlying Ruby object needs to stay alive.
    class CallbackSet
      attr_reader :write_fn, :error_fn

      def initialize(output_accumulator)
        @write_fn = FFI::Function.new(:void, %i[pointer pointer size_t]) do |_, data, len|
          output_accumulator << data.read_bytes(len)
        end
        @error_fn = FFI::Function.new(:void, %i[pointer string]) do |_, msg|
          raise Error, "libpng: #{msg}"
        end
      end
    end

    def coerce_pixel_format(value)
      sym = value.to_s.downcase.to_sym
      raise Error, "unknown pixel_format #{value.inspect}" unless FORMAT_TO_COLOR_TYPE.key?(sym)

      sym
    end

    def validate!
      raise Error, 'width must be positive' unless @width.positive?
      raise Error, 'height must be positive' unless @height.positive?
      raise Error, "unknown filter #{@filter_sym.inspect}" unless FILTER_MASK_BY_NAME.key?(@filter_sym)
      raise Error, 'compression_level must be 0..9' unless (0..9).cover?(@compression_level)
      unless INTERLACE_BY_NAME.key?(@interlace_sym)
        raise Error,
              "unknown interlace #{@interlace_sym.inspect} (expected :none or :adam7)"
      end

      validate_bit_depth!
      validate_palette! if palette_format?
      MetadataWriter.validate!(@metadata)
      return unless @pixels.bytesize < expected_size

      raise Error,
            "pixels too short: expected #{expected_size}, got #{@pixels.bytesize}"
    end

    def validate_bit_depth!
      if palette_format?
        raise Error, 'bit_depth must be 8 for palette format' unless @bit_depth == 8
      elsif !%i[gray rgb rgba].include?(@pixel_format_sym)
        # GA: only 8 supported here for now.
        raise Error, 'bit_depth must be 8' unless @bit_depth == 8
      elsif ![8, 16].include?(@bit_depth)
        raise Error, "bit_depth must be 8 or 16, got #{@bit_depth.inspect}"
      end
    end

    def validate_palette!
      raise Error, 'palette format requires palette: option' if @palette.nil?
      raise Error, 'palette must be an Array' unless @palette.is_a?(Array)
      raise Error, 'palette must have 1..256 entries' unless (1..256).cover?(@palette.length)

      @palette.each_with_index do |entry, i|
        next if entry.is_a?(Array) && [3, 4].include?(entry.length) && entry.all? do |v|
          v.is_a?(Integer) && v.between?(0, 255)
        end

        raise Error, "palette[#{i}] must be [r,g,b] or [r,g,b,a] with 0..255 values"
      end
    end

    def palette_format?
      @pixel_format_sym == :palette
    end

    def color_type
      FORMAT_TO_COLOR_TYPE[@pixel_format_sym]
    end

    def effective_bit_depth
      palette_format? ? 8 : @bit_depth
    end

    def interlace_method
      INTERLACE_BY_NAME[@interlace_sym]
    end

    def stride
      @width * bytes_per_pixel
    end

    def bytes_per_pixel
      return 1 if palette_format?

      BytesPerPixel.for_color_type(color_type, bit_depth: effective_bit_depth)
    end

    def expected_size
      stride * @height
    end

    def apply_compression(png_ptr)
      Libpng::Binding.png_set_compression_level(png_ptr, @compression_level)
    end

    def apply_filter(png_ptr)
      mask = FILTER_MASK_BY_NAME[@filter_sym]
      Libpng::Binding.png_set_filter(png_ptr, FILTER_HEURISTIC_DEFAULT, mask) if mask
    end

    def apply_palette(png_ptr, info_ptr)
      pal = @palette
      has_alpha = pal.any? { |e| e.length == 4 }
      pal_bytes = pal.map { |e| e.first(3) }.flatten.pack('C*')
      FFI::MemoryPointer.new(:uint8, pal_bytes.bytesize) do |pp|
        pp.write_bytes(pal_bytes)
        Libpng::Binding.png_set_PLTE(png_ptr, info_ptr, pp, pal.length)
      end
      return unless has_alpha

      alpha_bytes = pal.map { |e| e[3] || 255 }.pack('C*')
      FFI::MemoryPointer.new(:uint8, alpha_bytes.bytesize) do |ap|
        ap.write_bytes(alpha_bytes)
        Libpng::Binding.png_set_tRNS(png_ptr, info_ptr, ap, alpha_bytes.bytesize, nil)
      end
    end

    def destroy(png_ptr, info_ptr)
      return if png_ptr.null?

      FFI::MemoryPointer.new(:pointer) do |pp|
        pp.write_pointer(png_ptr)
        FFI::MemoryPointer.new(:pointer) do |ip|
          ip.write_pointer(info_ptr)
          Libpng::Binding.png_destroy_write_struct(pp, ip)
        end
      end
    end
  end
end
