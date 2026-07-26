# frozen_string_literal: true

require 'pathname'
require 'fileutils'

module Libpng
  module OHOS
    # OHOS-specific libpng build recipe. Inherits the standard
    # download/compile/install flow from Libpng::Recipe and layers on:
    #
    #   - NDK discovery + download (idempotent, ~1.5GB cached across runs)
    #   - Static zlib built with the same OHOS toolchain
    #   - CMake flags: -DCMAKE_TOOLCHAIN_FILE=<ohos.toolchain.cmake>
    #                  -DOHOS_ARCH=arm64-v8a -DOHOS_PLATFORM=OHOS
    #                  -DZLIB_LIBRARY=<static libz.a>
    #   - Post-install code signing via OHOS::CodeSigner
    #
    # The standard recipe already maps `aarch64-linux-ohos` to the right
    # cpu_type, cmake_system_name, and target_format, so those are not
    # overridden here.
    class Recipe < ::Libpng::Recipe
      def initialize
        super
        @ndk = OHOS::NDK.new(root: ROOT.join('ext/ohos/ndk'))
        @zlib = OHOS::ZlibBuilder.new(ndk: @ndk)
      end

      # Ensures NDK is downloaded and static zlib is built before the
      # libpng CMake configure runs. MiniPortile's #cook is idempotent
      # (checks downloaded?/configured?/installed?), so calling @zlib.cook
      # on every libpng cook is cheap when nothing changed.
      def cook
        @ndk.download unless @ndk.exist?
        raise 'OHOS NDK setup failed; see ext/ohos/setup-ndk.sh output' unless @ndk.exist?

        @zlib.cook
        super
      end

      def configure_defaults
        super + ohos_toolchain_flags + zlib_flags
      end

      def install
        super
        each_built_lib { |path| sign_lib(path) }
      end

      private

      def ohos_toolchain_flags
        [
          "-DCMAKE_TOOLCHAIN_FILE=#{@ndk.toolchain_path}",
          "-DOHOS_ARCH=#{OHOS::OHOS_ARCH}",
          "-DOHOS_PLATFORM=#{OHOS::OHOS_PLATFORM}",
          "-DCMAKE_SYSROOT=#{@ndk.sysroot_path}",
          '-DCMAKE_BUILD_TYPE=Release'
        ]
      end

      def zlib_flags
        [
          "-DZLIB_LIBRARY=#{@zlib.libz_path}",
          "-DZLIB_INCLUDE_DIR=#{@zlib.include_path}"
        ]
      end

      def sign_lib(path)
        signer = OHOS::CodeSigner.new(@ndk)
        raise "binary-sign-tool failed on #{path}; signing is mandatory for OHOS" unless signer.sign(Pathname.new(path))

        message("Signed #{path} (-selfSign 1)\n")
      end
    end
  end
end
