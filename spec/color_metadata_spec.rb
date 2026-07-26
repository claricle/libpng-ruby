# frozen_string_literal: true

require 'libpng'
require 'zlib'

RSpec.describe Libpng::ChunkWalker, '#color_chunks' do
  let(:base_png) { ChunkBuilder.minimal_rgba }

  it 'returns an empty Hash when no color chunks are present' do
    expect(described_class.new(base_png).color_chunks).to eq({})
  end

  it 'parses a gAMA chunk as a Float (value / 100000)' do
    # sRGB gamma = 0.45455 = 45455 / 100000
    png = ChunkBuilder.inject_after_ihdr(base_png, [['gAMA', [45_455].pack('N')]])
    expect(described_class.new(png).color_chunks).to eq(gamma: 0.45455)
  end

  it 'parses an sRGB chunk as a rendering intent integer (0..3)' do
    png = ChunkBuilder.inject_after_ihdr(base_png, [['sRGB', [0].pack('C')]])
    expect(described_class.new(png).color_chunks).to eq(srgb_intent: 0)

    png_perceptual = ChunkBuilder.inject_after_ihdr(base_png, [['sRGB', [1].pack('C')]])
    expect(described_class.new(png_perceptual).color_chunks).to eq(srgb_intent: 1)
  end

  it 'parses a cHRM chunk into 8 Float chromaticities' do
    chrm_bytes = [
      31_270, 32_900, # white point x/y (D65)
      64_000, 33_000, # red x/y
      30_000, 60_000, # green x/y
      15_000, 6_000   # blue x/y
    ].pack('N8')
    png = ChunkBuilder.inject_after_ihdr(base_png, [['cHRM', chrm_bytes]])
    result = described_class.new(png).color_chunks
    expect(result[:white_point_x]).to be_within(1e-9).of(0.31270)
    expect(result[:white_point_y]).to be_within(1e-9).of(0.32900)
    expect(result[:red_x]).to be_within(1e-9).of(0.64000)
    expect(result[:red_y]).to be_within(1e-9).of(0.33000)
    expect(result[:green_x]).to be_within(1e-9).of(0.30000)
    expect(result[:green_y]).to be_within(1e-9).of(0.60000)
    expect(result[:blue_x]).to be_within(1e-9).of(0.15000)
    expect(result[:blue_y]).to be_within(1e-9).of(0.06000)
  end

  it 'parses an iCCP chunk into name + decompressed profile bytes' do
    profile = 'fake-icc-profile-bytes-for-testing' * 4
    compressed = Zlib.deflate(profile)
    payload = "sRGB IEC61966-2.1\0\0#{compressed}"
    png = ChunkBuilder.inject_after_ihdr(base_png, [['iCCP', payload]])
    result = described_class.new(png).color_chunks
    expect(result[:icc_profile_name]).to eq('sRGB IEC61966-2.1')
    expect(result[:icc_profile]).to eq(profile)
  end

  it 'silently skips a malformed iCCP chunk (bad compression)' do
    payload = "Broken\0\0not-a-zlib-stream"
    png = ChunkBuilder.inject_after_ihdr(base_png,
                                         [['iCCP', payload], ['sRGB', [0].pack('C')]])
    expect(described_class.new(png).color_chunks).to eq(srgb_intent: 0)
  end

  it 'merges multiple color chunks present together (typical real-world PNG)' do
    # sRGB PNGs typically carry sRGB + gAMA + cHRM together. Color
    # management software reads sRGB first and ignores the others.
    gama_data = [45_455].pack('N')
    srgb_data = [0].pack('C')
    chrm_data = [31_270, 32_900, 64_000, 33_000, 30_000, 60_000, 15_000, 6_000].pack('N8')
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [['sRGB', srgb_data], ['gAMA', gama_data], ['cHRM', chrm_data]]
    )
    result = described_class.new(png).color_chunks
    expect(result[:srgb_intent]).to eq(0)
    expect(result[:gamma]).to be_within(1e-9).of(0.45455)
    expect(result[:red_x]).to be_within(1e-9).of(0.64000)
  end

  it 'ignores truncated gAMA/cHRM chunks rather than raising' do
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [['gAMA', "\x00\x00"],
       ['cHRM', [1, 2].pack('N*')],
       ['sRGB', [0].pack('C')]]
    )
    result = described_class.new(png).color_chunks
    # Truncated gAMA and cHRM are skipped; only sRGB survives.
    expect(result).to eq(srgb_intent: 0)
  end
end

RSpec.describe Libpng::DecodedImage, 'color metadata' do
  it 'is populated by Libpng.decode via the simplified read path' do
    png = ChunkBuilder.inject_after_ihdr(
      ChunkBuilder.minimal_rgba,
      [['gAMA', [45_455].pack('N')], ['sRGB', [0].pack('C')]]
    )
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.color[:gamma]).to be_within(1e-9).of(0.45455)
    expect(decoded.color[:srgb_intent]).to eq(0)
  end

  it 'defaults to an empty Hash when no color chunks are present' do
    decoded = Libpng.decode(ChunkBuilder.minimal_rgba, pixel_format: 'RGBA')
    expect(decoded.color).to eq({})
  end
end
