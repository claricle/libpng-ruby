# frozen_string_literal: true

require 'libpng'

# Round-trip and behavior tests for Libpng.decode_standard (the
# standard libpng read API path).
RSpec.describe Libpng, '.decode_standard' do
  let(:rgba) { (1..64).to_a.pack('C*') } # 4x4 RGBA
  let(:png_rgba) { Libpng.encode(4, 4, rgba, pixel_format: 'RGBA') }

  it 'round-trips an RGBA PNG to identical pixels' do
    decoded = Libpng.decode_standard(png_rgba, pixel_format: 'RGBA')
    expect(decoded.width).to eq(4)
    expect(decoded.height).to eq(4)
    expect(decoded.format).to eq('RGBA')
    expect(decoded.pixels).to eq(rgba)
  end

  it 'populates IHDR metadata fields like the simplified path' do
    decoded = Libpng.decode_standard(png_rgba, pixel_format: 'RGBA')
    expect(decoded.bit_depth).to eq(8)
    expect(decoded.color_type).to eq(Libpng::COLOR_TYPE_RGB_ALPHA)
    expect(decoded.interlace).to eq(Libpng::INTERLACE_NONE)
  end

  it 'populates text/color/phys metadata like the simplified path' do
    png = Libpng.encode_standard(2, 2, "\xff\x00\x00\xff\x00\xff\x00\xff\x00\x00\xff\xff\xff\xff\xff\xff",
                                 pixel_format: 'RGBA',
                                 text: { 'Title' => 'Sunset' },
                                 gamma: 0.45455,
                                 srgb_intent: 0)
    decoded = Libpng.decode_standard(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Title' => 'Sunset')
    expect(decoded.color[:gamma]).to be_within(1e-5).of(0.45455)
    expect(decoded.color[:srgb_intent]).to eq(0)
  end

  it 'produces byte-identical RGBA output to Libpng.decode for a non-palette source' do
    decoded_std = Libpng.decode_standard(png_rgba, pixel_format: 'RGBA')
    decoded_sim = Libpng.decode(png_rgba, pixel_format: 'RGBA')
    expect(decoded_std.pixels).to eq(decoded_sim.pixels)
  end

  it 'expands an RGB source to RGBA (adds opaque alpha)' do
    rgb = (1..48).to_a.pack('C*') # 4x4 RGB
    png_rgb = Libpng.encode(4, 4, rgb, pixel_format: 'RGB')
    decoded = Libpng.decode_standard(png_rgb, pixel_format: 'RGBA')
    expect(decoded.pixels.bytesize).to eq(4 * 4 * 4) # 16 RGBA pixels
    # First pixel: RGB was 1,2,3 -> RGBA should be 1,2,3,255
    expect(decoded.pixels.getbyte(3)).to eq(255)
  end

  it 'strips alpha when source has alpha but caller asks for RGB' do
    decoded = Libpng.decode_standard(png_rgba, pixel_format: 'RGB')
    expect(decoded.pixels.bytesize).to eq(4 * 4 * 3) # 16 RGB pixels
    expect(decoded.format).to eq('RGB')
  end

  it 'expands a grayscale source to RGBA' do
    gray = (1..16).to_a.pack('C*') # 4x4 GRAY
    png_gray = Libpng.encode(4, 4, gray, pixel_format: 'GRAY')
    decoded = Libpng.decode_standard(png_gray, pixel_format: 'RGBA')
    expect(decoded.pixels.bytesize).to eq(4 * 4 * 4)
    # First gray pixel was 1 -> RGBA should be 1,1,1,255 (gray expanded to RGB)
    expect(decoded.pixels.getbyte(0)).to eq(1)
    expect(decoded.pixels.getbyte(1)).to eq(1)
    expect(decoded.pixels.getbyte(2)).to eq(1)
    expect(decoded.pixels.getbyte(3)).to eq(255)
  end

  it 'expands a palette source to RGBA' do
    png = Libpng.encode_standard(2, 2, "\x00\x01\x01\x00",
                                 pixel_format: :palette,
                                 palette: [[255, 0, 0], [0, 255, 0]])
    decoded = Libpng.decode_standard(png, pixel_format: 'RGBA')
    # Index 0 = red -> RGBA(255, 0, 0, 255); Index 1 = green -> RGBA(0, 255, 0, 255)
    expect(decoded.pixels.bytes.first(4)).to eq([255, 0, 0, 255])
  end

  it 'demotes 16-bit source to 8-bit when bit_depth: 8 requested' do
    # Encode 16-bit RGBA: 2 pixels, 8 bytes per pixel channel (16-bit per channel)
    src = ([0x1234, 0x5678, 0x9ABC, 0xDEFF] * 4).pack('n*')
    png16 = Libpng.encode_standard(2, 2, src, pixel_format: 'RGBA', bit_depth: 16)
    decoded = Libpng.decode_standard(png16, pixel_format: 'RGBA', bit_depth: 8)
    expect(decoded.pixels.bytesize).to eq(2 * 2 * 4) # 4 RGBA pixels at 8-bit
  end

  it 'decodes Adam7-interlaced PNGs into the full image' do
    png = Libpng.encode_standard(4, 4, rgba, pixel_format: 'RGBA',
                                             interlace: :adam7)
    decoded = Libpng.decode_standard(png, pixel_format: 'RGBA')
    expect(decoded.pixels).to eq(rgba)
    expect(decoded.interlace).to eq(Libpng::INTERLACE_ADAM7)
  end

  it 'raises on non-PNG input' do
    expect do
      Libpng.decode_standard('not a png', pixel_format: 'RGBA')
    end.to raise_error(Libpng::Error)
  end

  it 'raises on nil input' do
    expect do
      Libpng.decode_standard(nil, pixel_format: 'RGBA')
    end.to raise_error(Libpng::Error, /nil/)
  end

  it 'rejects pixel_format: :palette (write-only)' do
    expect do
      Libpng.decode_standard(png_rgba, pixel_format: :palette)
    end.to raise_error(Libpng::Error, /write-only/)
  end

  it 'works inside a Ractor (Ractor safety)' do
    ractor = Ractor.new(png_rgba) do |bytes|
      Libpng.decode_standard(bytes, pixel_format: 'RGBA').pixels
    end
    expect(ractor_result(ractor)).to eq(rgba)
  end
end
