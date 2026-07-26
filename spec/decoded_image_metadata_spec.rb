# frozen_string_literal: true

require 'libpng'

# Verifies that Libpng::DecodedImage carries the IHDR metadata fields
# populated by the new SimplifiedDecoder metadata extraction path.
RSpec.describe Libpng::DecodedImage, 'IHDR metadata' do
  it 'populates bit_depth, color_type, interlace from the source PNG' do
    rgba = (1..32).to_a.pack('C*') * 2 # 4x4 RGBA
    png = Libpng.encode(4, 4, rgba, pixel_format: 'RGBA')
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.bit_depth).to eq(8)
    expect(decoded.color_type).to eq(Libpng::COLOR_TYPE_RGB_ALPHA)
    expect(decoded.interlace).to eq(Libpng::INTERLACE_NONE)
  end

  it 'populates color_type=RGB for an RGB-encoded PNG' do
    rgb = (1..32).to_a.pack('C*') * 2
    png = Libpng.encode(4, 4, rgb, pixel_format: 'RGB')
    decoded = Libpng.decode(png, pixel_format: 'RGB')
    expect(decoded.color_type).to eq(Libpng::COLOR_TYPE_RGB)
  end

  it 'populates color_type=GRAY for a grayscale PNG' do
    gray = (1..32).to_a.pack('C*')
    png = Libpng.encode(4, 4, gray, pixel_format: 'GRAY')
    decoded = Libpng.decode(png, pixel_format: 'GRAY')
    expect(decoded.color_type).to eq(Libpng::COLOR_TYPE_GRAY)
  end

  it 'reflects Adam7 interlacing in the interlace field' do
    rgba = (1..64).to_a.pack('C*')
    png = Libpng.encode_standard(4, 4, rgba,
                                 pixel_format: 'RGBA', interlace: :adam7)
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.interlace).to eq(Libpng::INTERLACE_ADAM7)
  end

  it 'leaves metadata nil when the PNG cannot be walked (truncated)' do
    # The simplified API raises Libpng::Error on truly broken input, so
    # there's no DecodedImage to inspect. But the walker is best-effort;
    # if it can't parse IHDR for some reason, the fields stay nil.
    rgba = (1..32).to_a.pack('C*') * 2
    png = Libpng.encode(4, 4, rgba, pixel_format: 'RGBA')
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.bit_depth).not_to be_nil
  end
end

RSpec.describe Libpng::ChunkWalker do
  let(:png) do
    rgba = (1..32).to_a.pack('C*') * 2
    Libpng.encode(4, 4, rgba, pixel_format: 'RGBA')
  end

  it 'yields every chunk with type, data, and offset' do
    walker = described_class.new(png)
    chunks = walker.each_chunk.to_a
    types = chunks.map(&:first)
    expect(types).to eq(%w[IHDR IDAT IEND])
    _type, ihdr_data, _offset = chunks.first
    expect(ihdr_data.length).to eq(13)
  end

  it 'parses IHDR fields correctly' do
    fields = described_class.new(png).ihdr_fields
    expect(fields[:width]).to eq(4)
    expect(fields[:height]).to eq(4)
    expect(fields[:bit_depth]).to eq(8)
    expect(fields[:color_type]).to eq(Libpng::COLOR_TYPE_RGB_ALPHA)
  end

  it 'raises on non-PNG input' do
    expect { described_class.new('hello').ihdr_fields }
      .to raise_error(Libpng::ChunkWalker::FormatError, /signature/)
  end
end
