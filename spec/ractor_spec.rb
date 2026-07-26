# frozen_string_literal: true

require 'libpng'

# Ractors were introduced in Ruby 3.0. The gemspec allows Ruby 2.7, so
# this file is a no-op there. On Ruby >= 3.0, verify that the FFI
# wrapper is genuinely Ractor-safe: the wrapper has no per-call shared
# mutable state (every call allocates its own png_image via
# FFI::MemoryPointer), and the module-level FFI function table is set
# up once at require time and is shareable across Ractors.
return unless defined?(Ractor)

RSpec.describe Libpng, 'Ractor safety' do
  let(:width) { 4 }
  let(:height) { 2 }
  let(:rgba) do
    [
      255, 0, 0, 255,    0, 255, 0, 255,    0, 0, 255, 255,    255, 255, 255, 255,
      255, 0, 255, 255,  255, 0, 255, 255,  255, 0, 255, 255,  255, 0, 255, 255
    ].pack('C*')
  end

  it 'encodes inside a Ractor and round-trips the bytes' do
    r = Ractor.new(width, height, rgba) do |w, h, px|
      Libpng.encode(w, h, px, pixel_format: 'RGBA')
    end
    png = r.take
    expect(png).to start_with("\x89PNG".b)
    expect(png.bytes[12..15].pack('C*')).to eq('IHDR')

    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.pixels).to eq(rgba)
  end

  it 'decodes inside a Ractor' do
    png = Libpng.encode(width, height, rgba, pixel_format: 'RGBA')
    r = Ractor.new(png) do |data|
      Libpng.decode(data, pixel_format: 'RGBA')
    end
    decoded = r.take
    expect(decoded.width).to eq(width)
    expect(decoded.height).to eq(height)
    expect(decoded.format).to eq('RGBA')
    expect(decoded.pixels).to eq(rgba)
  end

  it 'runs many Ractors concurrently with no locking' do
    png = Libpng.encode(width, height, rgba, pixel_format: 'RGBA')
    ractors = Array.new(8) do
      Ractor.new(png, rgba) do |data, expected|
        decoded = Libpng.decode(data, pixel_format: 'RGBA')
        decoded.pixels == expected
      end
    end
    expect(ractors.map(&:take)).to all(eq(true))
  end

  it 'mixes encode and decode across Ractors' do
    png = Libpng.encode(width, height, rgba, pixel_format: 'RGBA')
    enc_r = Ractor.new do
      Libpng.encode(2, 2, "\xFF" * 16, pixel_format: 'RGBA')
    end
    dec_r = Ractor.new(png) { |data| Libpng.decode(data, pixel_format: 'RGBA').pixels }

    expect(enc_r.take).to start_with("\x89PNG".b)
    expect(dec_r.take).to eq(rgba)
  end
end
