# frozen_string_literal: true

require 'libpng'

# Verifies that encode_standard is Ractor-safe. The wrapper's claim is
# that every call allocates its own png_struct via libpng's standard
# API, so concurrent calls from multiple Ractors don't share state.
RSpec.describe Libpng, '.encode_standard Ractor safety' do
  return unless defined?(Ractor)

  let(:width) { 4 }
  let(:height) { 2 }
  let(:rgba) do
    [
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255,
      255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255
    ].pack('C*')
  end

  it 'encodes via standard API inside a Ractor' do
    r = Ractor.new(width, height, rgba) do |w, h, px|
      Libpng.encode_standard(w, h, px, pixel_format: 'RGBA')
    end
    png = ractor_result(r)
    expect(png).to start_with("\x89PNG".b)
    expect(Libpng.decode(png, pixel_format: 'RGBA').pixels).to eq(rgba)
  end

  it 'runs many standard-encode Ractors concurrently' do
    ractors = Array.new(8) do
      Ractor.new(width, height, rgba) do |w, h, px|
        png = Libpng.encode_standard(w, h, px, pixel_format: 'RGBA',
                                               filter: :sub)
        Libpng.decode(png, pixel_format: 'RGBA').pixels == px
      end
    end
    expect(ractors.map { |r| ractor_result(r) }).to all(eq(true))
  end
end
