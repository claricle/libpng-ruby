# frozen_string_literal: true

require 'libpng'

# Round-trip tests for write-side metadata support on encode_standard.
# Each test encodes a PNG with one or more metadata options, decodes
# it via Libpng.decode (the simplified path, which uses ChunkWalker
# for metadata extraction), and verifies the metadata survives the
# trip.
RSpec.describe Libpng, 'write metadata via encode_standard' do
  let(:pixels) { (1..16).to_a.pack('C*') } # 1x1 RGBA (4 bytes), padded to 16

  # 2x2 RGBA fixture (16 bytes).
  let(:rgba) { "\xff\x00\x00\xff\x00\xff\x00\xff\x00\x00\xff\xff\xff\xff\xff\xff" }

  it 'round-trips a single tEXt chunk (ASCII value)' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             text: { 'Title' => 'Sunset' })
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Title' => 'Sunset')
  end

  it 'round-trips multiple tEXt chunks' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             text: { 'Title' => 'Sunset', 'Author' => 'Jane' })
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Title' => 'Sunset', 'Author' => 'Jane')
  end

  it 'emits iTXt (UTF-8) when value has non-ASCII characters' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             text: { 'Greeting' => 'こんにちは' })
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Greeting' => 'こんにちは')
  end

  it 'round-trips a gAMA chunk as a Float' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             gamma: 0.45455)
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.color[:gamma]).to be_within(1e-5).of(0.45455)
  end

  it 'round-trips an sRGB rendering intent' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             srgb_intent: 0)
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.color[:srgb_intent]).to eq(0)

    png_rel = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                                 srgb_intent: 1)
    decoded_rel = Libpng.decode(png_rel, pixel_format: 'RGBA')
    expect(decoded_rel.color[:srgb_intent]).to eq(1)
  end

  it 'round-trips a cHRM chunk (8 chromaticity floats)' do
    chrm = {
      white_point_x: 0.31270, white_point_y: 0.32900,
      red_x: 0.64000, red_y: 0.33000,
      green_x: 0.30000, green_y: 0.60000,
      blue_x: 0.15000, blue_y: 0.06000
    }
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             chromaticities: chrm)
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.color[:white_point_x]).to be_within(1e-5).of(0.31270)
    expect(decoded.color[:red_x]).to be_within(1e-5).of(0.64000)
    expect(decoded.color[:blue_y]).to be_within(1e-5).of(0.06000)
  end

  it 'round-trips a pHYs chunk (with DPI when unit=meter)' do
    png = Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                             phys: {
                                               pixels_per_unit_x: 3779,
                                               pixels_per_unit_y: 3779,
                                               unit: 1
                                             })
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.phys).to include(
      pixels_per_unit_x: 3779,
      pixels_per_unit_y: 3779,
      unit: 1
    )
    # 3779 ppm * 0.0254 in/m ~= 95.99 dpi
    expect(decoded.phys[:dpi_x]).to be_within(0.01).of(95.99)
    expect(decoded.phys[:dpi_y]).to be_within(0.01).of(95.99)
  end

  it 'emits all metadata chunks together in a typical sRGB PNG' do
    png = Libpng.encode_standard(
      2, 2, rgba, pixel_format: 'RGBA',
                  text: { 'Software' => 'libpng-ruby spec' },
                  gamma: 0.45455,
                  srgb_intent: 0,
                  chromaticities: {
                    white_point_x: 0.31270, white_point_y: 0.32900,
                    red_x: 0.64000, red_y: 0.33000,
                    green_x: 0.30000, green_y: 0.60000,
                    blue_x: 0.15000, blue_y: 0.06000
                  },
                  phys: { pixels_per_unit_x: 3779, pixels_per_unit_y: 3779, unit: 1 }
    )
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Software' => 'libpng-ruby spec')
    expect(decoded.color[:gamma]).to be_within(1e-5).of(0.45455)
    expect(decoded.color[:srgb_intent]).to eq(0)
    expect(decoded.phys[:dpi_x]).to be_within(0.01).of(95.99)
  end

  describe 'validation errors' do
    it 'rejects text with non-String value' do
      expect do
        Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                           text: { 'Bad' => 42 })
      end.to raise_error(Libpng::Error, /must be a String/)
    end

    it 'rejects gamma outside (0, 1]' do
      expect do
        Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA', gamma: 2.5)
      end.to raise_error(Libpng::Error, /gamma/)
    end

    it 'rejects srgb_intent outside 0..3' do
      expect do
        Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA', srgb_intent: 4)
      end.to raise_error(Libpng::Error, /srgb_intent/)
    end

    it 'rejects chromaticities missing required keys' do
      expect do
        Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                           chromaticities: { red_x: 0.5 })
      end.to raise_error(Libpng::Error, /chromaticities missing keys/)
    end

    it 'rejects phys with invalid unit' do
      expect do
        Libpng.encode_standard(2, 2, rgba, pixel_format: 'RGBA',
                                           phys: { pixels_per_unit_x: 100,
                                                   pixels_per_unit_y: 100,
                                                   unit: 2 })
      end.to raise_error(Libpng::Error, /phys\[:unit\]/)
    end
  end
end
