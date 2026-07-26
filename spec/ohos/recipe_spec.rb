# frozen_string_literal: true

require 'spec_helper'
require 'libpng/ohos'

# OHOS::Recipe#initialize creates an NDK instance pointed at gem-root
# /ext/ohos/ndk. We don't actually download/build in specs -- the
# configure_defaults + factory wiring is what's testable in-process.
RSpec.describe Libpng::OHOS::Recipe do
  describe 'inheritance' do
    it 'inherits from Libpng::Recipe' do
      expect(described_class.ancestors).to include(Libpng::Recipe)
    end
  end

  describe '.new' do
    it 'does not download the NDK on construction (lazy)' do
      # If we got here without raising or hanging, initialization was
      # side-effect-free. Actual download happens on #cook.
      expect { described_class.new }.not_to raise_error
    end
  end

  describe '#configure_defaults' do
    # Build without invoking cook -- configure_defaults is pure data.
    subject(:flags) { described_class.new.configure_defaults.join(' ') }

    it 'includes the OHOS toolchain file' do
      expect(flags).to match(/-DCMAKE_TOOLCHAIN_FILE=.*ohos\.toolchain\.cmake/)
    end

    it 'sets OHOS_ARCH=arm64-v8a' do
      expect(flags).to include('-DOHOS_ARCH=arm64-v8a')
    end

    it 'sets OHOS_PLATFORM=OHOS' do
      expect(flags).to include('-DOHOS_PLATFORM=OHOS')
    end

    it 'passes the static zlib path (ZLIB_LIBRARY=...libz.a)' do
      expect(flags).to match(/-DZLIB_LIBRARY=.*libz\.a/)
    end

    it 'passes the zlib include dir (ZLIB_INCLUDE_DIR=.../include)' do
      expect(flags).to match(%r{-DZLIB_INCLUDE_DIR=.*/include})
    end

    it 'passes the OHOS sysroot' do
      expect(flags).to match(%r{-DCMAKE_SYSROOT=.*llvm-19/sysroot})
    end

    it 'uses Release build type' do
      expect(flags).to include('-DCMAKE_BUILD_TYPE=Release')
    end

    it 'keeps PNG_SHARED=ON from the parent recipe' do
      expect(flags).to include('-DPNG_SHARED=ON')
    end

    it 'keeps PNG_STATIC=OFF from the parent recipe' do
      expect(flags).to include('-DPNG_STATIC=OFF')
    end
  end
end
