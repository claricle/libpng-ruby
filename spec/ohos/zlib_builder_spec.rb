# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'libpng/ohos'

RSpec.describe Libpng::OHOS::ZlibBuilder do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:ndk) { Libpng::OHOS::NDK.new(root: root) }

  before do
    %w[
      ohos-sdk/linux/build/cmake/ohos.toolchain.cmake
      llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang
      ohos-sdk/linux/toolchains/lib/binary-sign-tool
    ].each do |rel|
      path = root.join(rel)
      path.dirname.mkpath
      FileUtils.touch(path)
    end
    root.join('llvm-19/sysroot/usr/lib/aarch64-linux-ohos').mkpath
  end

  after { FileUtils.rm_rf(root) }

  describe 'ZLIB_URL' do
    it 'embeds the pinned ZLIB_VERSION' do
      expect(described_class::ZLIB_URL).to include(described_class::ZLIB_VERSION)
    end

    it 'points at zlib.net/fossils/' do
      expect(described_class::ZLIB_URL).to start_with('https://zlib.net/fossils/')
      expect(described_class::ZLIB_URL).to end_with('.tar.gz')
    end
  end

  describe 'ZLIB_SHA256' do
    it 'is a 64-character hex string' do
      expect(described_class::ZLIB_SHA256).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '#configure_defaults' do
    subject(:flags) { described_class.new(ndk: ndk).configure_defaults }

    it 'passes the OHOS toolchain file' do
      expect(flags.join(' ')).to match(/-DCMAKE_TOOLCHAIN_FILE=.*ohos\.toolchain\.cmake/)
    end

    it 'sets OHOS_ARCH=arm64-v8a' do
      expect(flags).to include('-DOHOS_ARCH=arm64-v8a')
    end

    it 'sets OHOS_PLATFORM=OHOS' do
      expect(flags).to include('-DOHOS_PLATFORM=OHOS')
    end

    it 'passes the OHOS sysroot' do
      expect(flags.join(' ')).to match(%r{-DCMAKE_SYSROOT=.*llvm-19/sysroot})
    end

    it 'requests a static build' do
      expect(flags).to include('-DBUILD_SHARED_LIBS=OFF')
    end

    it 'uses Release build type' do
      expect(flags).to include('-DCMAKE_BUILD_TYPE=Release')
    end
  end

  describe '#libz_path' do
    it 'ends in lib/libz.a' do
      path = described_class.new(ndk: ndk).libz_path
      expect(path.to_s).to end_with('lib/libz.a')
      expect(path).to be_a(Pathname)
    end
  end

  describe '#include_path' do
    it 'ends in include' do
      path = described_class.new(ndk: ndk).include_path
      expect(path.to_s).to end_with('/include')
      expect(path).to be_a(Pathname)
    end
  end
end
