# frozen_string_literal: true

require 'libpng'
require 'zlib'

RSpec.describe Libpng::ChunkWalker, '#text_chunks' do
  let(:base_png) { ChunkBuilder.minimal_rgba }

  it 'returns an empty Hash when the PNG has no text chunks' do
    expect(described_class.new(base_png).text_chunks).to eq({})
  end

  it 'parses a single tEXt chunk (Latin-1 keyword -> UTF-8 value)' do
    png = ChunkBuilder.inject_after_ihdr(base_png, [['tEXt', "Title\0Sunset"]])
    expect(described_class.new(png).text_chunks).to eq('Title' => 'Sunset')
  end

  it 'parses multiple tEXt chunks (different keywords)' do
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [
        ['tEXt', "Title\0Sunset"],
        ['tEXt', "Author\0Jane Q"]
      ]
    )
    expect(described_class.new(png).text_chunks)
      .to eq('Title' => 'Sunset', 'Author' => 'Jane Q')
  end

  it 'last chunk wins when the same keyword repeats' do
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [
        ['tEXt', "Title\0Sunset"],
        ['tEXt', "Title\0Dawn"]
      ]
    )
    expect(described_class.new(png).text_chunks).to eq('Title' => 'Dawn')
  end

  it 'transcodes Latin-1 bytes above 0x7F to UTF-8 (tEXt)' do
    # "café" in Latin-1: 0x63 0x61 0x66 0xE9
    png = ChunkBuilder.inject_after_ihdr(base_png, [['tEXt', "Word\0caf\xE9"]])
    expect(described_class.new(png).text_chunks).to eq('Word' => 'café')
  end

  it 'parses a zTXt chunk (zlib-inflated, Latin-1 transcoded)' do
    compressed = Zlib.deflate('Hello, World!')
    payload = "Comment\0\0#{compressed}"
    png = ChunkBuilder.inject_after_ihdr(base_png, [['zTXt', payload]])
    expect(described_class.new(png).text_chunks).to eq('Comment' => 'Hello, World!')
  end

  it 'silently skips a malformed zTXt chunk but keeps parsing others' do
    bad_ztxt = "Bad\0\0not-a-zlib-stream"
    good_text = "Title\0Sunset"
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [['zTXt', bad_ztxt], ['tEXt', good_text]]
    )
    expect(described_class.new(png).text_chunks).to eq('Title' => 'Sunset')
  end

  it 'parses an uncompressed iTXt chunk (UTF-8 text)' do
    # keyword\0 compression_flag(1=0) compression_method(1=0)
    # language_tag\0 translated_keyword\0 text
    payload = "Title\0\0\0en\0Title\0Sunset"
    png = ChunkBuilder.inject_after_ihdr(base_png, [['iTXt', payload]])
    expect(described_class.new(png).text_chunks).to eq('Title' => 'Sunset')
  end

  it 'parses a compressed iTXt chunk (zlib-inflated, UTF-8)' do
    compressed = Zlib.deflate('sunset over the bay')
    payload = "Description\0\x01\0en\0Description\0#{compressed}"
    png = ChunkBuilder.inject_after_ihdr(base_png, [['iTXt', payload]])
    expect(described_class.new(png).text_chunks)
      .to eq('Description' => 'sunset over the bay')
  end

  it 'preserves UTF-8 multibyte characters in iTXt' do
    payload = "Greeting\0\0\0en\0Greeting\0こんにちは"
    png = ChunkBuilder.inject_after_ihdr(base_png, [['iTXt', payload]])
    expect(described_class.new(png).text_chunks).to eq('Greeting' => 'こんにちは')
  end

  it 'silently skips a malformed iTXt chunk (missing fields)' do
    truncated = "Title\0" # no flag/method/lang/text
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [['iTXt', truncated], ['tEXt', "Other\0Kept"]]
    )
    expect(described_class.new(png).text_chunks).to eq('Other' => 'Kept')
  end
end

RSpec.describe Libpng::DecodedImage, 'text metadata' do
  it 'is populated by Libpng.decode via the simplified read path' do
    base_png = ChunkBuilder.minimal_rgba
    png = ChunkBuilder.inject_after_ihdr(
      base_png,
      [['tEXt', "Author\0Jane"], ['tEXt', "Title\0Sunset"]]
    )
    decoded = Libpng.decode(png, pixel_format: 'RGBA')
    expect(decoded.text).to eq('Author' => 'Jane', 'Title' => 'Sunset')
  end

  it 'defaults to an empty Hash when no text chunks are present' do
    decoded = Libpng.decode(ChunkBuilder.minimal_rgba, pixel_format: 'RGBA')
    expect(decoded.text).to eq({})
  end

  it 'round-trips through Ractor moving (frozen-keyword Struct compatibility)' do
    png = ChunkBuilder.inject_after_ihdr(ChunkBuilder.minimal_rgba,
                                         [['tEXt', "Author\0Jane"]])
    ractor = Ractor.new(png) do |bytes|
      Libpng.decode(bytes, pixel_format: 'RGBA').text
    end
    expect(ractor_result(ractor)).to eq('Author' => 'Jane')
  end
end
