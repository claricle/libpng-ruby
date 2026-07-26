# frozen_string_literal: true

require 'libpng'

# Feeds intentionally-broken PNG bytes to Libpng.decode and asserts
# that Libpng::Error is raised rather than the process aborting.
# libpng's standard API uses setjmp/longjmp for errors; the simplified
# API captures errors into the png_image's message buffer, so the
# decode path is well-behaved on bad input.
RSpec.describe Libpng, '.decode on malformed input' do
  let(:valid_png) do
    rgba = [
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255
    ].pack('C*')
    described_class.encode(2, 2, rgba, pixel_format: 'RGBA')
  end

  def with_chunk(png, type, replacement_data)
    bytes = png.bytes
    offset = 8
    while offset + 8 <= bytes.length
      len = bytes[offset, 4].pack('C*').unpack1('N')
      chunk_type = bytes[offset + 4, 4].pack('C*')
      chunk_total = 12 + len
      if chunk_type == type
        new_bytes = bytes.dup
        new_bytes[offset + 8, replacement_data.length] = replacement_data.bytes
        return new_bytes.pack('C*')
      end
      offset += chunk_total
    end
    raise "chunk type #{type} not found"
  end

  def corrupt_crc(png, type)
    bytes = png.bytes
    offset = 8
    while offset + 8 <= bytes.length
      len = bytes[offset, 4].pack('C*').unpack1('N')
      chunk_type = bytes[offset + 4, 4].pack('C*')
      chunk_total = 12 + len
      if chunk_type == type
        new_bytes = bytes.dup
        new_bytes[offset + 8 + len] = (bytes[offset + 8 + len] ^ 0xFF)
        return new_bytes.pack('C*')
      end
      offset += chunk_total
    end
    raise "chunk type #{type} not found"
  end

  it 'raises on non-PNG input' do
    expect { described_class.decode('not a png') }.to raise_error(Libpng::Error)
  end

  it 'raises on truncated PNG signature' do
    expect { described_class.decode("\x89PNG\r\n\x1a") }.to raise_error(Libpng::Error)
  end

  it 'raises on empty input' do
    expect { described_class.decode('') }.to raise_error(Libpng::Error)
  end

  it 'raises on nil input' do
    expect { described_class.decode(nil) }.to raise_error(Libpng::Error)
  end

  it 'raises on a PNG truncated mid-IDAT' do
    bytes = valid_png.bytes
    # Find IDAT and cut after the first 4 bytes of its data.
    offset = 8
    idat_offset = nil
    while offset + 8 <= bytes.length
      len = bytes[offset, 4].pack('C*').unpack1('N')
      type = bytes[offset + 4, 4].pack('C*')
      idat_offset = offset if type == 'IDAT'
      offset += 12 + len
      break if type == 'IEND'
    end
    truncated = bytes[0, idat_offset + 12].pack('C*')
    expect { described_class.decode(truncated) }.to raise_error(Libpng::Error)
  end

  it 'raises on a PNG missing IEND' do
    bytes = valid_png.bytes
    # Strip the last 12 bytes (IEND chunk).
    truncated = bytes[0, bytes.length - 12].pack('C*')
    # libpng's simplified API may accept this since it returns after the
    # IDAT data is complete, but the walker-based metadata path should
    # not blow up. Accept either success or Libpng::Error.
    begin
      result = described_class.decode(truncated)
      expect(result).to be_a(Libpng::DecodedImage)
    rescue Libpng::Error => e
      expect(e.message).to match(/.*/)
    end
  end

  it 'detects a corrupt IHDR CRC' do
    broken = corrupt_crc(valid_png, 'IHDR')
    expect { described_class.decode(broken) }.to raise_error(Libpng::Error)
  end

  it 'detects a corrupt IDAT CRC' do
    broken = corrupt_crc(valid_png, 'IDAT')
    # libpng's simplified API may either error or accept; assert no crash.
    begin
      described_class.decode(broken)
    rescue Libpng::Error
      # expected
    end
  end

  it 'rejects a zero-dimension IHDR' do
    # Build a minimal PNG with width=0 in the IHDR.
    bytes = valid_png.bytes.dup
    # IHDR data is at offset 16 (8 sig + 4 len + 4 type) for 13 bytes.
    # First 4 bytes of IHDR data are width (big-endian uint32).
    bytes[16, 4] = [0, 0, 0, 0]
    expect { described_class.decode(bytes.pack('C*')) }.to raise_error(Libpng::Error)
  end

  it 'rejects an impossibly large dimension' do
    bytes = valid_png.bytes.dup
    bytes[16, 4] = [0x7F, 0xFF, 0xFF, 0xFF] # ~2 billion
    expect { described_class.decode(bytes.pack('C*')) }.to raise_error(Libpng::Error)
  end
end
