# frozen_string_literal: true

require 'pathname'

module Libpng
  module OHOS
    # Pure-data handle to an extracted OHOS NDK installation. Discovers
    # the four critical paths the build needs (toolchain cmake, clang,
    # sysroot, binary-sign-tool), exposes them as Pathnames, and can
    # invoke ext/ohos/setup-ndk.sh to populate the directory if missing.
    #
    # Does NOT run any NDK binary itself -- that's the caller's job.
    # This keeps the class testable without qemu/binfmt setup: specs just
    # touch empty files at the expected paths and assert accessors.
    class NDK
      ROOT_RELATIVE = Pathname.new('ext/ohos/ndk').freeze

      def initialize(root: default_root)
        @root = Pathname.new(root)
      end

      def exist?
        toolchain_path.exist? &&
          clang_path.exist? &&
          sysroot_path.exist? &&
          sign_tool_path.exist?
      end

      def toolchain_path
        sdk_dir.join('build/cmake/ohos.toolchain.cmake')
      end

      def clang_path
        llvm_dir.join('bin/aarch64-unknown-linux-ohos-clang')
      end

      def clangxx_path
        llvm_dir.join('bin/aarch64-unknown-linux-ohos-clang++')
      end

      def sysroot_path
        root.join('llvm-19/sysroot')
      end

      def sign_tool_path
        sdk_dir.join('toolchains/lib/binary-sign-tool')
      end

      def cmake_path
        sdk_dir.join('build-tools/cmake/bin/cmake')
      end

      attr_reader :root

      # Downloads + extracts the NDK via ext/ohos/setup-ndk.sh. No-op
      # if #exist?. Returns true on success, false otherwise.
      def download
        return true if exist?

        script = recipe_root.join('ext/ohos/setup-ndk.sh')
        system(script.to_s, '--prefix', @root.to_s)
      end

      private

      def sdk_dir
        root.join('ohos-sdk/linux')
      end

      def llvm_dir
        root.join('llvm-19/llvm')
      end

      def recipe_root
        Pathname.new(File.expand_path('../..', __dir__))
      end

      def default_root
        recipe_root.join(ROOT_RELATIVE)
      end
    end
  end
end
