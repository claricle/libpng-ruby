# frozen_string_literal: true

require 'libpng'

RSpec.describe Libpng, '.encode_standard' do
  def extract_idat(png)
    offset = 8
    idat = String.new
    while offset + 8 <= png.bytesize
      len = png.bytes[offset, 4].pack('C*').unpack1('N')
      type = png.bytes[offset + 4, 4].pack('C*')
      idat << png.bytes[offset + 8, len].pack('C*') if type == 'IDAT'
      offset += 12 + len
      break if type == 'IEND'
    end
    idat
  end

  let(:width) { 4 }
  let(:height) { 2 }
  let(:rgba) do
    [
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
      255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255
    ].pack('C*')
  end

  describe 'round-trip' do
    it 'encodes RGBA and decodes back unchanged' do
      png = described_class.encode_standard(width, height, rgba, pixel_format: 'RGBA')
      expect(png).to start_with("\x89PNG".b)
      expect(png.bytes[12..15].pack('C*')).to eq('IHDR')

      decoded = described_class.decode(png, pixel_format: 'RGBA')
      expect(decoded.width).to eq(width)
      expect(decoded.height).to eq(height)
      expect(decoded.pixels).to eq(rgba)
    end

    it 'encodes RGB and round-trips via RGB decode' do
      rgb = rgba.bytes.each_slice(4).map { |px| px.first(3) }.flatten.pack('C*')
      png = described_class.encode_standard(width, height, rgb, pixel_format: 'RGB')
      decoded = described_class.decode(png, pixel_format: 'RGB')
      expect(decoded.pixels).to eq(rgb)
    end

    it 'encodes grayscale pixels' do
      gray = [0, 64, 128, 255, 32, 96, 160, 224].pack('C*')
      png = described_class.encode_standard(4, 2, gray, pixel_format: 'GRAY')
      decoded = described_class.decode(png, pixel_format: 'GRAY')
      expect(decoded.pixels).to eq(gray)
    end

    it 'encodes grayscale+alpha pixels' do
      ga = [10, 200, 20, 180, 30, 160, 40, 140].pack('C*')
      png = described_class.encode_standard(2, 2, ga, pixel_format: 'GA')
      decoded = described_class.decode(png, pixel_format: 'GA')
      expect(decoded.pixels).to eq(ga)
    end
  end

  describe 'chunk layout' do
    it 'emits only IHDR, IDAT, IEND (no sRGB/gAMA/cHRM)' do
      png = described_class.encode_standard(width, height, rgba, pixel_format: 'RGBA')
      types = []
      offset = 8
      while offset + 8 <= png.bytesize
        len = png.bytes[offset, 4].pack('C*').unpack1('N')
        type = png.bytes[offset + 4, 4].pack('C*')
        types << type
        offset += 12 + len
        break if type == 'IEND'
      end
      expect(types).to eq(%w[IHDR IDAT IEND])
    end
  end

  describe 'filter option' do
    %i[default adaptive none sub up avg paeth all].each do |filter|
      it "accepts filter: #{filter.inspect} and produces a decodable PNG" do
        png = described_class.encode_standard(width, height, rgba,
                                              pixel_format: 'RGBA', filter: filter)
        decoded = described_class.decode(png, pixel_format: 'RGBA')
        expect(decoded.pixels).to eq(rgba)
      end
    end

    it 'produces a valid PNG for :none even when it differs from the default size' do
      default = described_class.encode_standard(width, height, rgba,
                                                pixel_format: 'RGBA', filter: :default)
      none = described_class.encode_standard(width, height, rgba,
                                             pixel_format: 'RGBA', filter: :none)
      # The IDAT sizes differ depending on content (adaptive filtering
      # may or may not help). What matters is both decode to the same
      # pixels and :none forces a recognizable difference in IDAT bytes.
      expect(none.bytes[0, 33]).to eq(default.bytes[0, 33]) # same IHDR
      idat_default = extract_idat(default)
      idat_none = extract_idat(none)
      expect(idat_none).not_to eq(idat_default)
    end

    it 'raises on unknown filter' do
      expect do
        described_class.encode_standard(width, height, rgba,
                                        pixel_format: 'RGBA', filter: :bogus)
      end.to raise_error(Libpng::Error, /unknown filter/)
    end
  end

  describe 'compression_level option' do
    (0..9).each do |level|
      it "accepts compression_level: #{level}" do
        png = described_class.encode_standard(width, height, rgba,
                                              pixel_format: 'RGBA',
                                              compression_level: level)
        decoded = described_class.decode(png, pixel_format: 'RGBA')
        expect(decoded.pixels).to eq(rgba)
      end
    end

    it 'rejects out-of-range levels' do
      expect do
        described_class.encode_standard(width, height, rgba,
                                        pixel_format: 'RGBA', compression_level: 10)
      end.to raise_error(Libpng::Error, /compression_level/)

      expect do
        described_class.encode_standard(width, height, rgba,
                                        pixel_format: 'RGBA', compression_level: -1)
      end.to raise_error(Libpng::Error, /compression_level/)
    end
  end

  describe 'error handling' do
    it 'raises on non-positive width' do
      expect { described_class.encode_standard(0, 1, '') }.to raise_error(Libpng::Error, /width/)
    end

    it 'raises on non-positive height' do
      expect { described_class.encode_standard(1, 0, '') }.to raise_error(Libpng::Error, /height/)
    end

    it 'raises on too-short pixel buffer' do
      expect do
        described_class.encode_standard(4, 4, 'x' * 4, pixel_format: 'RGBA')
      end.to raise_error(Libpng::Error, /too short/)
    end

    it 'raises on unknown pixel_format' do
      expect do
        described_class.encode_standard(1, 1, "\xFF" * 4, pixel_format: 'BOGUS')
      end.to raise_error(Libpng::Error, /unknown pixel_format/)
    end

    it 'rejects byte-order variant formats (BGRA, ARGB, etc.)' do
      expect do
        described_class.encode_standard(1, 1, "\xFF" * 4, pixel_format: 'BGRA')
      end.to raise_error(Libpng::Error, /BGRA/)
    end
  end

  describe 'compared to simplified encode' do
    it 'produces the same chunk layout (IHDR, IDAT, IEND)' do
      simplified = described_class.encode(width, height, rgba, pixel_format: 'RGBA')
      standard = described_class.encode_standard(width, height, rgba, pixel_format: 'RGBA')
      # IHDR headers should be identical
      expect(simplified.bytes[0, 33]).to eq(standard.bytes[0, 33])

      # The IDAT contents may differ due to filter selection differences
      # between the simplified and standard APIs; both decode to the
      # same pixels.
      expect(described_class.decode(standard, pixel_format: 'RGBA').pixels)
        .to eq(described_class.decode(simplified, pixel_format: 'RGBA').pixels)
    end
  end
end
