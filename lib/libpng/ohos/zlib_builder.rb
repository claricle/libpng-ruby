# frozen_string_literal: true

require 'mini_portile2'
require 'pathname'

module Libpng
  module OHOS
    # Builds zlib as a static library (libz.a) using the OHOS NDK
    # toolchain. The resulting archive is linked into libpng16.so so
    # the OHOS gem doesn't depend on OHOS's non-standard
    # libshared_libz.z.so at runtime.
    #
    # zlib was chosen as a static dep rather than dynamically linking
    # against the OHOS sysroot because:
    #   - libpng's CMake find_package(ZLIB) expects libz.so
    #   - OHOS ships zlib under the SONAME libshared_libz.z.so
    #   - patchelf post-processing is fragile
    # Static linking sidesteps the whole problem.
    class ZlibBuilder < MiniPortileCMake
      # Pinned zlib source URL + sha256. Bump deliberately.
      ZLIB_VERSION = '1.3.1'
      ZLIB_URL = "https://zlib.net/fossils/zlib-#{ZLIB_VERSION}.tar.gz"
      ZLIB_SHA256 = '9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23'

      # libpng's recipe extends MiniPortileCMake and redirects @target into
      # the gem's working tree. We mirror that layout so the zlib port
      # lives next to libpng's port under ports/.
      def initialize(ndk:)
        super('zlib', ZLIB_VERSION)
        @files << { url: ZLIB_URL, sha256: ZLIB_SHA256 }
        @ndk = ndk
        @target = Libpng::Recipe::ROOT.join(@target).to_s
      end

      def configure_defaults
        super +
          [
            "-DCMAKE_TOOLCHAIN_FILE=#{@ndk.toolchain_path}",
            "-DOHOS_ARCH=#{OHOS::OHOS_ARCH}",
            "-DOHOS_PLATFORM=#{OHOS::OHOS_PLATFORM}",
            "-DCMAKE_SYSROOT=#{@ndk.sysroot_path}",
            '-DBUILD_SHARED_LIBS=OFF',
            '-DCMAKE_INSTALL_LIBDIR=lib',
            '-DCMAKE_BUILD_TYPE=Release'
          ]
      end

      def libz_path
        Pathname.new(port_path).join('lib/libz.a')
      end

      def include_path
        Pathname.new(port_path).join('include')
      end
    end
  end
end
