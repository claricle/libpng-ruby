# frozen_string_literal: true

require 'libpng'

RSpec.describe Libpng do
  let(:width) { 4 }
  let(:height) { 2 }
  let(:rgba) do
    # Row-major, top-down: row 0 = red, green, blue, white; row 1 = all magenta.
    [
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
      255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255
    ].pack('C*')
  end

  describe '.encode and .decode round-trip' do
    it 'writes RGBA pixels and reads them back unchanged' do
      png = described_class.encode(width, height, rgba, pixel_format: 'RGBA')
      expect(png).to start_with("\x89PNG".b)
      expect(png.bytes[12..15].pack('C*')).to eq('IHDR')

      decoded = described_class.decode(png, pixel_format: 'RGBA')
      expect(decoded.width).to eq(width)
      expect(decoded.height).to eq(height)
      expect(decoded.format).to eq('RGBA')
      expect(decoded.pixels).to eq(rgba)
    end

    it 'encodes RGB input and round-trips via RGB decode' do
      rgb = rgba.bytes.each_slice(4).map { |px| px.first(3) }.flatten.pack('C*')
      png = described_class.encode(width, height, rgb, pixel_format: 'RGB')
      decoded = described_class.decode(png, pixel_format: 'RGB')
      expect(decoded.width).to eq(width)
      expect(decoded.height).to eq(height)
      expect(decoded.pixels).to eq(rgb)
    end

    it 'encodes grayscale pixels' do
      gray = [0, 64, 128, 255, 32, 96, 160, 224].pack('C*')
      png = described_class.encode(4, 2, gray, pixel_format: 'GRAY')
      decoded = described_class.decode(png, pixel_format: 'GRAY')
      expect(decoded.pixels).to eq(gray)
    end
  end

  describe '.encode error handling' do
    it 'raises on non-positive width' do
      expect { described_class.encode(0, 1, '') }.to raise_error(Libpng::Error, /width/)
    end

    it 'raises on non-positive height' do
      expect { described_class.encode(1, 0, '') }.to raise_error(Libpng::Error, /height/)
    end

    it 'raises on too-short pixel buffer' do
      expect { described_class.encode(4, 4, 'x' * 4, pixel_format: 'RGBA') }
        .to raise_error(Libpng::Error, /too short/)
    end

    it 'raises on unknown pixel_format' do
      expect { described_class.encode(1, 1, "\xFF" * 4, pixel_format: 'BOGUS') }
        .to raise_error(Libpng::Error, /unknown pixel_format/)
    end
  end

  describe '.decode error handling' do
    it 'raises on truncated input' do
      expect { described_class.decode("\x89PNG\r\n\x1a\n partial") }
        .to raise_error(Libpng::Error)
    end

    it 'raises on non-PNG input' do
      expect { described_class.decode('not a png') }
        .to raise_error(Libpng::Error)
    end
  end
end
