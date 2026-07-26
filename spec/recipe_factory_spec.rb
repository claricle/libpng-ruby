# frozen_string_literal: true

require 'spec_helper'
require 'libpng/recipe'

RSpec.describe Libpng::Recipe, '.for_target' do
  describe '.for_target' do
    it 'returns the base Recipe for nil (host build, source gem)' do
      expect(described_class.for_target(nil)).to be(Libpng::Recipe)
    end

    it 'returns the base Recipe for non-OHOS linux targets' do
      expect(described_class.for_target('x86_64-linux')).to be(Libpng::Recipe)
      expect(described_class.for_target('aarch64-linux-musl')).to be(Libpng::Recipe)
    end

    it 'returns the base Recipe for darwin/mingw targets' do
      expect(described_class.for_target('arm64-darwin')).to be(Libpng::Recipe)
      expect(described_class.for_target('x64-mingw-ucrt')).to be(Libpng::Recipe)
    end

    it 'returns OHOS::Recipe for aarch64-linux-ohos' do
      expect(described_class.for_target('aarch64-linux-ohos')).to be(Libpng::OHOS::Recipe)
    end

    it 'returns OHOS::Recipe for any *-ohos target (future-proofing)' do
      expect(described_class.for_target('x86_64-linux-ohos')).to be(Libpng::OHOS::Recipe)
    end
  end

  describe '.ohos_target?' do
    it 'returns true for *-ohos strings' do
      expect(described_class.ohos_target?('aarch64-linux-ohos')).to be(true)
      expect(described_class.ohos_target?('x86_64-linux-ohos')).to be(true)
    end

    it 'returns false for non-ohos strings' do
      expect(described_class.ohos_target?('aarch64-linux-musl')).to be(false)
      expect(described_class.ohos_target?('aarch64-linux')).to be(false)
    end

    it 'returns false for non-String inputs (defensive)' do
      expect(described_class.ohos_target?(nil)).to be(false)
      expect(described_class.ohos_target?(:aarch64_linux_ohos)).to be(false)
    end
  end
end
