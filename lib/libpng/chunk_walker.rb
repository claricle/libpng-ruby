# frozen_string_literal: true

require 'zlib'

module Libpng
  # Walks a PNG byte buffer chunk-by-chunk. Used to strip ancillary
  # chunks (sRGB, gAMA, cHRM, iCCP, etc.) that libpng's simplified
  # write API emits by default, and to extract metadata (IHDR fields,
  # text chunks, gAMA, pHYs) during decode.
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

    private

    def verify_signature
      sig = @bytes.first(8)
      raise FormatError, 'not a PNG file (bad signature)' unless sig == SIGNATURE
    end
  end
end
