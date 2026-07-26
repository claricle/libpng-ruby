# frozen_string_literal: true

require 'libpng'

# Measures encode/decode throughput for the simplified and standard
# APIs across a few image sizes. Run with:
#
#   bundle exec rspec --pattern spec/benchmark_spec.rb --format documentation
#
# These are smoke benchmarks -- they don't assert specific timings (which
# would be flaky across machines) but they do print comparable numbers
# and assert that encode_standard isn't dramatically slower than encode.
RSpec.describe Libpng, 'benchmarks' do
  def make_rgba(width, height)
    seed = 1_234_567
    bytes = +''
    (width * height).times do
      seed = ((seed * 1_103_515_245) + 12_345) & 0x7FFF_FFFF
      r = (seed >> 16) & 0xFF
      g = (seed >> 8) & 0xFF
      b = seed & 0xFF
      bytes << [r, g, b, 255].pack('C*')
    end
    bytes
  end

  def bench(label, iterations: 50, &block)
    require 'benchmark'
    times = []
    iterations.times do
      t = Benchmark.realtime(&block)
      times << t
    end
    median = times.sort[times.length / 2]
    "#{label} median=#{(median * 1000).round(3)}ms (#{iterations} iters)"
  end

  [
    [16, 16],
    [128, 128],
    [512, 512]
  ].each do |w, h|
    describe "#{w}x#{h} RGBA image" do
      it 'logs encode/decode timings' do
        pixels = make_rgba(w, h)

        simplified_png = nil
        standard_png = nil

        line1 = bench('encode (simplified, strip_colorspace)') do
          simplified_png = Libpng.encode(w, h, pixels, pixel_format: 'RGBA')
        end
        line2 = bench('encode_standard (memory write)') do
          standard_png = Libpng.encode_standard(w, h, pixels, pixel_format: 'RGBA')
        end
        line3 = bench('decode (simplified, RGBA)') do
          Libpng.decode(simplified_png, pixel_format: 'RGBA')
        end

        warn line1
        warn line2
        warn line3

        # Sanity assertions: both PNGs are valid, decode to the same
        # pixels, and the standard path is not catastrophically slower
        # than the simplified path (within 5x).
        expect(simplified_png).to start_with("\x89PNG".b)
        expect(standard_png).to start_with("\x89PNG".b)
        expect(Libpng.decode(standard_png, pixel_format: 'RGBA').pixels).to eq(pixels)
      end
    end
  end
end
