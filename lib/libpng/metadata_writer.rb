# frozen_string_literal: true

module Libpng
  # Validates and writes PNG metadata chunks (text, gamma, sRGB,
  # chromaticities, ICC profile, pHYs) onto a (png_ptr, info_ptr)
  # pair. Extracted from StandardEncoder so the encoder stays focused
  # on pixel + IHDR/PLTE concerns; this module owns the metadata story.
  #
  # The same module is reusable by any future encoder that wants to
  # emit metadata -- it doesn't depend on StandardEncoder's state.
  module MetadataWriter
    REQUIRED_CHRM_KEYS = %i[
      white_point_x white_point_y
      red_x red_y
      green_x green_y
      blue_x blue_y
    ].freeze

    module_function

    # Validate the metadata portion of an options Hash. Raises
    # Libpng::Error on any invalid value. Keys with nil values are
    # treated as absent.
    def validate!(options)
      validate_text!(options[:text]) if options[:text]
      validate_gamma!(options[:gamma]) if options[:gamma]
      validate_srgb_intent!(options[:srgb_intent]) if options[:srgb_intent]
      validate_chromaticities!(options[:chromaticities]) if options[:chromaticities]
      validate_icc_profile!(options[:icc_profile]) if options[:icc_profile]
      validate_phys!(options[:phys]) if options[:phys]
    end

    # Apply metadata writers in spec-defined order: text first
    # (tEXt/zTXt/iTXt come after PLTE but before oFFs/pHYs in the
    # canonical chunk ordering), then color-space chunks (sRGB, gAMA,
    # cHRM, iCCP), then pHYs. libpng sorts these into the right file
    # order on write, so call order here just needs to be consistent.
    def apply(png_ptr, info_ptr, options)
      apply_text(png_ptr, info_ptr, options[:text]) if options[:text]
      apply_srgb(png_ptr, info_ptr, options[:srgb_intent]) if options[:srgb_intent]
      apply_gamma(png_ptr, info_ptr, options[:gamma]) if options[:gamma]
      apply_chromaticities(png_ptr, info_ptr, options[:chromaticities]) if options[:chromaticities]
      apply_icc_profile(png_ptr, info_ptr, options[:icc_profile]) if options[:icc_profile]
      apply_phys(png_ptr, info_ptr, options[:phys]) if options[:phys]
    end

    def validate_text!(text)
      raise Error, 'text must be a Hash' unless text.is_a?(Hash)

      text.each do |key, value|
        unless key.is_a?(String) && key.length.between?(1, 79)
          raise Error, "text key #{key.inspect} must be a 1..79 char ASCII String"
        end
        raise Error, "text[#{key.inspect}] must be a String, got #{value.class}" unless value.is_a?(String)
      end
    end

    def validate_gamma!(gamma)
      return if gamma.is_a?(Float) && gamma.positive? && gamma <= 1.0

      raise Error, 'gamma must be a Float 0 < g <= 1'
    end

    def validate_srgb_intent!(intent)
      return if intent.is_a?(Integer) && (0..3).cover?(intent)

      raise Error, 'srgb_intent must be an Integer 0..3'
    end

    def validate_chromaticities!(chrm)
      missing = REQUIRED_CHRM_KEYS.reject { |k| chrm.is_a?(Hash) && chrm.key?(k) }
      return if missing.empty?

      raise Error, "chromaticities missing keys: #{missing.inspect}"
    end

    def validate_icc_profile!(profile)
      unless profile.is_a?(Hash) && profile[:name].is_a?(String) && profile[:data].is_a?(String)
        raise Error, 'icc_profile must be a Hash with :name (String) and :data (binary String)'
      end
      return if profile[:name].length.between?(1, 79)

      raise Error, 'icc_profile[:name] must be 1..79 chars'
    end

    def validate_phys!(phys)
      unless phys.is_a?(Hash) && phys.key?(:pixels_per_unit_x) && phys.key?(:pixels_per_unit_y) && phys.key?(:unit)
        raise Error, 'phys must be a Hash with :pixels_per_unit_x, :pixels_per_unit_y, :unit'
      end
      unless phys[:unit].is_a?(Integer) && [0, 1].include?(phys[:unit])
        raise Error, 'phys[:unit] must be 0 (unknown) or 1 (meters)'
      end

      [phys[:pixels_per_unit_x], phys[:pixels_per_unit_y]].each do |v|
        unless v.is_a?(Integer) && v.between?(0, 0xFFFFFFFF)
          raise Error, 'phys pixels_per_unit_* must be Integer 0..2^32-1'
        end
      end
    end

    def apply_text(png_ptr, info_ptr, text)
      entries = text.map { |k, v| Libpng::TextEntry.new(key: k, value: v) }
      Libpng::TextWriter.call(png_ptr, info_ptr, entries)
    end

    def apply_srgb(png_ptr, info_ptr, intent)
      Libpng::Binding.png_set_sRGB(png_ptr, info_ptr, intent)
    end

    def apply_gamma(png_ptr, info_ptr, gamma)
      Libpng::Binding.png_set_gAMA(png_ptr, info_ptr, gamma)
    end

    def apply_chromaticities(png_ptr, info_ptr, chrm)
      Libpng::Binding.png_set_cHRM(
        png_ptr, info_ptr,
        chrm[:white_point_x], chrm[:white_point_y],
        chrm[:red_x], chrm[:red_y],
        chrm[:green_x], chrm[:green_y],
        chrm[:blue_x], chrm[:blue_y]
      )
    end

    def apply_icc_profile(png_ptr, info_ptr, profile)
      data = profile[:data]
      FFI::MemoryPointer.new(:uint8, data.bytesize) do |buf|
        buf.write_bytes(data)
        Libpng::Binding.png_set_iCCP(png_ptr, info_ptr, profile[:name], 0, buf, data.bytesize)
      end
    end

    def apply_phys(png_ptr, info_ptr, phys)
      Libpng::Binding.png_set_pHYs(png_ptr, info_ptr,
                                   phys[:pixels_per_unit_x],
                                   phys[:pixels_per_unit_y],
                                   phys[:unit])
    end
  end
end
