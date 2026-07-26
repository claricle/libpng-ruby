# frozen_string_literal: true

require 'libpng'

RSpec.describe Libpng::StandardEncoder, 'new options' do
  let(:width) { 4 }
  let(:height) { 4 }
  let(:rgba) do
    (0...(width * height * 4)).map { |i| (i * 17) & 0xFF }.pack('C*')
  end

  describe 'interlace option' do
    it 'defaults to :none (single IDAT, sequential rows)' do
      png = Libpng.encode_standard(width, height, rgba, pixel_format: 'RGBA')
      fields = Libpng::ChunkWalker.new(png).ihdr_fields
      expect(fields[:interlace]).to eq(Libpng::INTERLACE_NONE)
    end

    it 'accepts interlace: :adam7' do
      png = Libpng.encode_standard(width, height, rgba,
                                   pixel_format: 'RGBA', interlace: :adam7)
      fields = Libpng::ChunkWalker.new(png).ihdr_fields
      expect(fields[:interlace]).to eq(Libpng::INTERLACE_ADAM7)
      expect(Libpng.decode(png, pixel_format: 'RGBA').pixels).to eq(rgba)
    end

    it 'rejects unknown interlace values' do
      expect do
        Libpng.encode_standard(width, height, rgba,
                               pixel_format: 'RGBA', interlace: :bogus)
      end.to raise_error(Libpng::Error, /interlace/)
    end

    it 'produces a larger PNG than :none for typical input' do
      none = Libpng.encode_standard(width, height, rgba,
                                    pixel_format: 'RGBA', interlace: :none)
      adam7 = Libpng.encode_standard(width, height, rgba,
                                     pixel_format: 'RGBA', interlace: :adam7)
      # Adam7 splits the image into 7 passes; for small images the
      # per-pass overhead exceeds the compression savings.
      expect(adam7.bytesize).to be > none.bytesize
    end
  end

  describe 'bit_depth option' do
    it 'defaults to 8' do
      png = Libpng.encode_standard(width, height, rgba, pixel_format: 'RGBA')
      fields = Libpng::ChunkWalker.new(png).ihdr_fields
      expect(fields[:bit_depth]).to eq(8)
    end

    it 'accepts bit_depth: 16 (caller provides 8 bytes per pixel as 2-byte LE channels)' do
      # 16-bit RGBA: 8 bytes per pixel (2 bytes per channel, host-order).
      pixels = (0...(width * height * 8)).map { |i| (i * 17) & 0xFF }.pack('C*')
      png = Libpng.encode_standard(width, height, pixels,
                                   pixel_format: 'RGBA', bit_depth: 16)
      fields = Libpng::ChunkWalker.new(png).ihdr_fields
      expect(fields[:bit_depth]).to eq(16)
    end

    it 'rejects bit_depth: 16 for palette format' do
      pal = [[0, 0, 0], [255, 255, 255]]
      expect do
        Libpng.encode_standard(2, 2, [0, 1, 0, 1].pack('C*'),
                               pixel_format: :palette, palette: pal, bit_depth: 16)
      end.to raise_error(Libpng::Error, /bit_depth must be 8 for palette/)
    end

    it 'rejects unsupported bit depths' do
      expect do
        Libpng.encode_standard(2, 2, rgba[0, 16],
                               pixel_format: 'RGBA', bit_depth: 12)
      end.to raise_error(Libpng::Error, /bit_depth/)
    end
  end

  describe 'palette option' do
    let(:palette) do
      [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]]
    end
    let(:indices) { [0, 1, 2, 3, 3, 2, 1, 0].pack('C*') } # 2x4

    it 'encodes a paletted image and round-trips via RGBA decode' do
      png = Libpng.encode_standard(2, 4, indices,
                                   pixel_format: :palette, palette: palette)
      fields = Libpng::ChunkWalker.new(png).ihdr_fields
      expect(fields[:color_type]).to eq(Libpng::COLOR_TYPE_PALETTE)

      # Decoded as RGBA, each index expands to its palette color.
      decoded = Libpng.decode(png, pixel_format: 'RGBA')
      expected_rgba = indices.bytes.map { |i| palette[i] + [255] }.flatten.pack('C*')
      expect(decoded.pixels).to eq(expected_rgba)
    end

    it 'accepts palette entries with alpha' do
      pal_alpha = [[255, 0, 0, 128], [0, 255, 0, 200], [0, 0, 255, 255], [255, 255, 255, 0]]
      png = Libpng.encode_standard(2, 2, [0, 1, 2, 3].pack('C*'),
                                   pixel_format: :palette, palette: pal_alpha)
      expect(png).to start_with("\x89PNG".b)
    end

    it 'raises when palette is missing for :palette format' do
      expect do
        Libpng.encode_standard(2, 2, [0, 1, 0, 1].pack('C*'),
                               pixel_format: :palette)
      end.to raise_error(Libpng::Error, /palette: option/)
    end

    it 'raises when palette has too many entries' do
      big_pal = Array.new(257) { [0, 0, 0] }
      expect do
        Libpng.encode_standard(2, 2, [0, 0, 0, 0].pack('C*'),
                               pixel_format: :palette, palette: big_pal)
      end.to raise_error(Libpng::Error, /1..256/)
    end

    it 'raises on malformed palette entry' do
      bad_pal = [[255, 0], [0, 255, 0]] # first entry has wrong arity
      expect do
        Libpng.encode_standard(2, 2, [0, 1, 0, 1].pack('C*'),
                               pixel_format: :palette, palette: bad_pal)
      end.to raise_error(Libpng::Error, /palette\[0\]/)
    end
  end
end
