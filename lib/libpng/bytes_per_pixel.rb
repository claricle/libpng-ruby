# frozen_string_literal: true

module Libpng
  # Maps pixel formats to bytes-per-pixel. Used by both the simplified
  # and standard encoders / decoders to compute row stride.
  #
  # Pure data class -- no I/O, no allocations beyond the lookup itself.
  module BytesPerPixel
    # Per-channel byte count for the supported bit depths. Linear (16-bit)
    # formats aren't currently exposed via the simplified API path; the
    # standard encoder uses this table when bit_depth: 16 is requested.
    CHANNEL_BYTES_8_BIT  = 1
    CHANNEL_BYTES_16_BIT = 2

    # Channels per PNG_COLOR_TYPE_* (png.h).
    CHANNELS_BY_COLOR_TYPE = {
      Libpng::COLOR_TYPE_GRAY => 1,
      Libpng::COLOR_TYPE_GRAY_ALPHA => 2,
      Libpng::COLOR_TYPE_RGB => 3,
      Libpng::COLOR_TYPE_RGB_ALPHA => 4,
      Libpng::COLOR_TYPE_PALETTE => 1
    }.freeze

    def self.for_format(format_value)
      case format_value
      when Libpng::FORMAT_GRAY then 1
      when Libpng::FORMAT_GA, Libpng::FORMAT_AG then 2
      when Libpng::FORMAT_RGB, Libpng::FORMAT_BGR then 3
      when Libpng::FORMAT_RGBA, Libpng::FORMAT_ARGB,
        Libpng::FORMAT_BGRA, Libpng::FORMAT_ABGR then 4
      else
        raise Libpng::Error, "no bytes-per-pixel mapping for format 0x#{format_value.to_s(16)}"
      end
    end

    def self.for_color_type(color_type, bit_depth: 8)
      channels = CHANNELS_BY_COLOR_TYPE[color_type] ||
                 raise(Libpng::Error, "unknown color_type #{color_type}")
      channel_bytes = bit_depth == 16 ? CHANNEL_BYTES_16_BIT : CHANNEL_BYTES_8_BIT
      channels * channel_bytes
    end
  end
end
