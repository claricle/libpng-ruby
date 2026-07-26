# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'libpng/ohos'

RSpec.describe Libpng::OHOS::NDK do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:ndk) { described_class.new(root: root) }

  def touch_rel(rel)
    path = root.join(rel)
    path.dirname.mkpath
    FileUtils.touch(path)
  end

  before do
    touch_rel('ohos-sdk/linux/build/cmake/ohos.toolchain.cmake')
    touch_rel('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang')
    touch_rel('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang++')
    touch_rel('ohos-sdk/linux/toolchains/lib/binary-sign-tool')
    touch_rel('ohos-sdk/linux/build-tools/cmake/bin/cmake')
    root.join('llvm-19/sysroot/usr/lib/aarch64-linux-ohos').mkpath
  end

  after { FileUtils.rm_rf(root) }

  describe '#exist?' do
    it 'returns true when all critical paths are present' do
      expect(ndk.exist?).to be(true)
    end

    it 'returns false when the toolchain file is missing' do
      root.join('ohos-sdk/linux/build/cmake/ohos.toolchain.cmake').delete
      expect(ndk.exist?).to be(false)
    end

    it 'returns false when the clang is missing' do
      root.join('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang').delete
      expect(ndk.exist?).to be(false)
    end

    it 'returns false when the sysroot is missing' do
      root.join('llvm-19/sysroot').rmtree
      expect(ndk.exist?).to be(false)
    end

    it 'returns false when binary-sign-tool is missing' do
      root.join('ohos-sdk/linux/toolchains/lib/binary-sign-tool').delete
      expect(ndk.exist?).to be(false)
    end
  end

  describe '#toolchain_path' do
    it 'points at ohos.toolchain.cmake under the SDK dir' do
      expect(ndk.toolchain_path.to_s).to end_with('ohos-sdk/linux/build/cmake/ohos.toolchain.cmake')
    end

    it 'is a Pathname' do
      expect(ndk.toolchain_path).to be_a(Pathname)
    end
  end

  describe '#clang_path' do
    it 'points at aarch64-unknown-linux-ohos-clang' do
      expect(ndk.clang_path.to_s).to end_with('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang')
    end
  end

  describe '#clangxx_path' do
    it 'points at aarch64-unknown-linux-ohos-clang++' do
      expect(ndk.clangxx_path.to_s).to end_with('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang++')
    end
  end

  describe '#sysroot_path' do
    it 'points at the OHOS sysroot dir' do
      expect(ndk.sysroot_path.to_s).to end_with('llvm-19/sysroot')
    end
  end

  describe '#sign_tool_path' do
    it 'points at binary-sign-tool under toolchains/lib' do
      expect(ndk.sign_tool_path.to_s).to end_with('ohos-sdk/linux/toolchains/lib/binary-sign-tool')
    end
  end

  describe '#cmake_path' do
    it 'points at the NDK-bundled cmake binary' do
      expect(ndk.cmake_path.to_s).to end_with('ohos-sdk/linux/build-tools/cmake/bin/cmake')
    end
  end

  describe '#root' do
    it 'returns the Pathname passed to the constructor' do
      expect(ndk.root).to eq(root)
    end
  end
end
