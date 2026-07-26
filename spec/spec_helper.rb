# frozen_string_literal: true

require 'libpng'
require 'zlib'

# Builds PNG byte buffers with arbitrary ancillary chunks for testing.
# Specs use this to construct tEXt/zTXt/iTXt/gAMA/cHRM/sRGB/iCCP test
# fixtures that the existing public encode API does not yet emit.
module ChunkBuilder
  SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*').force_encoding('ASCII-8BIT')

  module_function

  # Returns the on-the-wire bytes for a single PNG chunk of the given
  # type. CRC is computed automatically.
  def chunk(type, data)
    data = data.dup.force_encoding('ASCII-8BIT')
    ([data.length].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N'))
      .force_encoding('ASCII-8BIT')
  end

  # Takes a base PNG (e.g. output of Libpng.encode) and returns a new
  # PNG with the supplied (type, data) pairs injected right after IHDR.
  # PNG permits color chunks (gAMA/cHRM/sRGB/iCCP) and text chunks
  # (tEXt/zTXt/iTXt) between IHDR and IDAT, so this position works for
  # all chunk types we currently test.
  def inject_after_ihdr(base_png, chunks)
    rebuilt = SIGNATURE.dup
    injected = false
    Libpng::ChunkWalker.new(base_png).each_chunk do |type, data, _|
      rebuilt << chunk(type, data)
      next unless type == 'IHDR' && !injected

      chunks.each { |t, d| rebuilt << chunk(t, d) }
      injected = true
    end
    rebuilt
  end

  # Returns a minimal 2x2 RGBA PNG; reusable as a base for fixtures.
  def minimal_rgba
    Libpng.encode(2, 2, "\xff\x00\x00\xff\x00\xff\x00\xff\x00\x00\xff\xff\xff\xff\xff\xff",
                  pixel_format: 'RGBA')
  end
end

# Reads the result of a Ractor across Ruby versions: Ruby 4.0 (Dec 2025)
# removed Ractor#take in favor of Ractor#value. Specs need to work on
# both, so prefer #value when present.
def ractor_result(ractor)
  ractor.respond_to?(:value) ? ractor.value : ractor.take
end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
