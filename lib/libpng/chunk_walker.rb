# frozen_string_literal: true

require 'zlib'

module Libpng
  # Walks a PNG byte buffer chunk-by-chunk. Used to strip ancillary
  # chunks (sRGB, gAMA, cHRM, iCCP, etc.) that libpng's simplified
  # write API emits by default, and to extract metadata (IHDR fields,
  # text chunks, color chunks, pHYs) during decode.
  #
  # The chunk layout is documented in the PNG spec:
  #   [4 bytes length][4 bytes type][length bytes data][4 bytes CRC]
  # Length and CRC are big-endian uint32. The signature is the 8 bytes
  # before the first chunk: 89 50 4E 47 0D 0A 1A 0A.
  class ChunkWalker
    SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].freeze

    # Raised on any structural issue: bad signature, chunk running past
    # EOF, CRC mismatch, missing IEND.
    class FormatError < Error; end

    # PNG gAMA fixed-point scale (per spec: gamma = uint32 / 100000).
    GAMMA_SCALE = 100_000.0

    # PNG cHRM fixed-point scale (per spec: chromaticity = uint32 / 100000).
    CHRM_SCALE = 100_000.0

    def initialize(png_bytes)
      @bytes = png_bytes.bytes
    end

    # Iterate every chunk in order. Yields [type_string, data_bytes,
    # offset] to the block. Returns an Enumerator if no block given.
    def each_chunk
      return enum_for(:each_chunk) unless block_given?

      verify_signature
      offset = 8
      until offset + 8 > @bytes.length
        len = @bytes[offset, 4].pack('C*').unpack1('N')
        type = @bytes[offset + 4, 4].pack('C*')
        chunk_total = 12 + len
        if offset + chunk_total > @bytes.length
          raise FormatError,
                "PNG chunk at offset #{offset} (#{type}) runs past EOF"
        end

        crc_input = @bytes[offset + 4, 4 + len].pack('C*')
        crc_actual = @bytes[offset + 8 + len, 4].pack('C*').unpack1('N')
        crc_expected = Zlib.crc32(crc_input)
        raise FormatError, "PNG chunk CRC mismatch at offset #{offset} (#{type})" unless crc_actual == crc_expected

        data = @bytes[offset + 8, len].pack('C*')
        yield type, data, offset

        offset += chunk_total
        break if type == 'IEND'
      end
    end

    # Returns a new binary String containing only the PNG signature
    # plus IHDR, IDAT, and IEND chunks. Other chunks (sRGB, gAMA, cHRM,
    # iCCP, tEXt, zTXt, iTXt, bKGD, pHYs, oFFs, tIME, sCAL, hIST,
    # sPLT, unknown chunks) are dropped.
    def strip_ancillary
      kept = SIGNATURE.pack('C*')
      each_chunk do |type, data, _offset|
        next unless %w[IHDR IDAT IEND].include?(type)

        len_bytes = [data.length].pack('N')
        type_bytes = type
        crc_bytes = [Zlib.crc32(type_bytes + data)].pack('N')
        kept << len_bytes << type_bytes << data << crc_bytes
      end
      kept.force_encoding('ASCII-8BIT')
    end

    # Returns the raw IHDR data bytes (13 bytes), or raises if missing.
    def ihdr_data
      each_chunk { |type, data, _| return data if type == 'IHDR' }
      raise FormatError, 'PNG has no IHDR chunk'
    end

    # Parse IHDR fields. Returns a Hash with :width, :height,
    # :bit_depth, :color_type, :compression, :filter, :interlace.
    def ihdr_fields
      data = ihdr_data
      raise FormatError, "IHDR is #{data.length} bytes, expected 13" unless data.length == 13

      width, height, bd, ct, comp, filt, intc = data.unpack('NNCCCCC')
      {
        width: width,
        height: height,
        bit_depth: bd,
        color_type: ct,
        compression: comp,
        filter: filt,
        interlace: intc
      }
    end

    # Parse text chunks (tEXt, zTXt, iTXt) into a flat Hash of
    # keyword -> UTF-8 String. When the same keyword appears in
    # multiple chunks, the last occurrence wins (PNG spec permits
    # this; behavior matches libpng's read path).
    #
    # - tEXt: Latin-1 keyword + Latin-1 value, transcoded to UTF-8.
    # - zTXt: Latin-1 keyword + zlib-compressed Latin-1 value,
    #   inflated then transcoded to UTF-8.
    # - iTXt: UTF-8 keyword + UTF-8 value (optionally zlib-compressed),
    #   with separate language tag and translated keyword that are
    #   dropped here (callers who need them should walk chunks directly).
    #
    # Malformed chunks are silently skipped: a single broken zTXt
    # should not poison the rest of the decode.
    def text_chunks
      result = {}
      each_chunk do |type, data, _|
        case type
        when 'tEXt'
          parse_text(data, result)
        when 'zTXt'
          parse_ztxt(data, result)
        when 'iTXt'
          parse_itxt(data, result)
        end
      end
      result
    end

    # Parse color-space chunks (gAMA, cHRM, sRGB, iCCP) into a Hash.
    # Returns Symbol keys:
    #
    #   :gamma                -> Float (gAMA, value/100000)
    #   :white_point_x, :white_point_y -> Float (cHRM)
    #   :red_x, :red_y, :green_x, :green_y, :blue_x, :blue_y -> Float
    #   :srgb_intent           -> Integer 0..3 (sRGB)
    #   :icc_profile_name      -> UTF-8 String (iCCP, profile name)
    #   :icc_profile           -> binary String (iCCP, decompressed bytes)
    #
    # Malformed chunks (e.g. truncated cHRM, bad iCCP compression) are
    # silently skipped. ICC profiles can be large (10KB-1MB); callers
    # who don't need them should walk chunks manually rather than call
    # this method.
    def color_chunks
      result = {}
      each_chunk do |type, data, _|
        case type
        when 'gAMA'
          parse_gama(data, result)
        when 'cHRM'
          parse_chrm(data, result)
        when 'sRGB'
          parse_srgb(data, result)
        when 'iCCP'
          parse_iccp(data, result)
        end
      end
      result
    end

    private

    def verify_signature
      sig = @bytes.first(8)
      raise FormatError, 'not a PNG file (bad signature)' unless sig == SIGNATURE
    end

    # Split a binary string at the first NUL byte. Returns [head, tail]
    # where head excludes the NUL and tail is everything after. Returns
    # [nil, nil] when no NUL is present.
    def split_at_null(bytes)
      idx = bytes.index("\x00")
      return [nil, nil] if idx.nil?

      [bytes[0, idx], bytes[(idx + 1)..]]
    end

    # Force Latin-1 byte sequence into UTF-8. Bytes 0x80-0xFF that have
    # no assigned meaning in ISO-8859-1 still round-trip through this
    # encoding because Latin-1 is a strict superset of the byte values.
    def latin1_to_utf8(bytes)
      bytes.force_encoding('ISO-8859-1').encode('UTF-8')
    end

    def parse_text(data, result)
      key, value = split_at_null(data)
      return if key.nil?

      result[key] = latin1_to_utf8(value)
    end

    def parse_ztxt(data, result)
      key, rest = split_at_null(data)
      return if key.nil? || rest.nil? || rest.length < 2

      _compression_method = rest.getbyte(0)
      inflated = Zlib.inflate(rest[1..])
      result[key] = latin1_to_utf8(inflated)
    rescue Zlib::Error
      # Skip malformed zTXt rather than failing the whole decode.
    end

    def parse_itxt(data, result)
      # iTXt layout:
      #   keyword\0
      #   compression_flag (1 byte, 0 = uncompressed, 1 = zlib)
      #   compression_method (1 byte, 0 = zlib/deflate)
      #   language_tag\0 (ASCII, may be empty)
      #   translated_keyword\0 (UTF-8, may be empty)
      #   text (UTF-8, optionally zlib-compressed)
      key, rest = split_at_null(data)
      return if key.nil? || rest.nil? || rest.length < 3

      compression_flag = rest.getbyte(0)
      _compression_method = rest.getbyte(1)
      _lang, after_lang = split_at_null(rest[2..])
      return if after_lang.nil?

      _translated, text_bytes = split_at_null(after_lang)
      return if text_bytes.nil?

      text_bytes = Zlib.inflate(text_bytes) if compression_flag == 1
      result[key] = text_bytes.force_encoding('UTF-8')
    rescue Zlib::Error
      # Skip malformed iTXt rather than failing the whole decode.
    end

    def parse_gama(data, result)
      return if data.length < 4

      result[:gamma] = data.unpack1('N') / GAMMA_SCALE
    end

    def parse_chrm(data, result)
      return if data.length < 32

      wp_x, wp_y, rx, ry, gx, gy, bx, by = data.unpack('N8')
      result[:white_point_x] = wp_x / CHRM_SCALE
      result[:white_point_y] = wp_y / CHRM_SCALE
      result[:red_x] = rx / CHRM_SCALE
      result[:red_y] = ry / CHRM_SCALE
      result[:green_x] = gx / CHRM_SCALE
      result[:green_y] = gy / CHRM_SCALE
      result[:blue_x] = bx / CHRM_SCALE
      result[:blue_y] = by / CHRM_SCALE
    end

    def parse_srgb(data, result)
      return if data.empty?

      result[:srgb_intent] = data.getbyte(0)
    end

    def parse_iccp(data, result)
      # iCCP layout:
      #   profile_name\0
      #   compression_method (1 byte, must be 0 = zlib/deflate)
      #   compressed_profile (zlib stream)
      name, rest = split_at_null(data)
      return if name.nil? || rest.nil? || rest.length < 2

      _compression_method = rest.getbyte(0)
      profile = Zlib.inflate(rest[1..])
      result[:icc_profile_name] = name.force_encoding('UTF-8')
      result[:icc_profile] = profile
    rescue Zlib::Error
      # Skip malformed iCCP rather than failing the whole decode.
    end
  end
end
