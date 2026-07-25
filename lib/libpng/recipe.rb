require 'rbconfig'
require 'mini_portile2'
require 'pathname'
require 'tmpdir'
require 'open3'
require_relative 'version'

module Libpng
  # MiniPortile-based recipe for building libpng from source. Mirrors the
  # pattern used by emf2svg-ruby: during `gem install`, ext/extconf.rb
  # invokes Recipe#cook, which downloads the libpng source tarball, runs
  # configure + make, and installs the shared library into the gem's lib/
  # directory. The pre-compiled gems (built via `rake gem:native:<plat>`)
  # ship the .so/.dylib/.dll and disable extconf.rb entirely.
  class Recipe < MiniPortileCMake
    # Pinned libpng source URL + sha256. Bump deliberately to refresh
    # the upstream — and remember to update both fields together.
    LIBPNG_URL = "https://downloads.sourceforge.net/project/libpng/libpng16/#{Libpng::LIBPNG_VERSION}/libpng-#{Libpng::LIBPNG_VERSION}.tar.gz".freeze
    # sha256 of the libpng-X.Y.Z.tar.gz tarball. Verify with:
    #   curl -sL <URL> | shasum -a 256
    LIBPNG_SHA256 = '68f3d83a79d81dfcb0a439d62b411aa257bb4973d7c67cd1ff8bdf8d011538cd'.freeze

    ROOT = Pathname.new(File.expand_path('../..', __dir__))

    def initialize
      super('libpng', Libpng::LIBPNG_VERSION)

      @files << {
        url: LIBPNG_URL,
        sha256: LIBPNG_SHA256
      }

      @target = ROOT.join(@target).to_s
      @printed = {}
    end

    # libpng ships a CMake build alongside the autotools one. We use CMake
    # for consistency with mini_portile2's defaults and to handle Windows
    # cleanly (autotools on native Windows is fragile).
    # No additional configuration is needed; defaults build PNG_SHARED=ON
    # and PNG_STATIC=OFF, which is what we want.

    def cook_if_not
      cook unless File.exist?(checkpoint)
    end

    def cook
      super
      FileUtils.touch(checkpoint)
    end

    def checkpoint
      File.join(@target, "#{name}-#{version}-#{target_platform}.installed")
    end

    def configure_defaults
      # Build a static+self-contained shared library: we only ship the .so
      # to consumers, so libpng's transitive dep on zlib must be linked in.
      opts = super
      opts << '-DPNG_SHARED=ON'
      opts << '-DPNG_STATIC=OFF'
      opts << '-DPNG_TESTS=OFF'
      opts << '-DPNG_FRAMEWORK=OFF'
      # macOS: avoid the .framework build; we want a plain .dylib.
      opts << '-DCMAKE_INSTALL_LIBDIR=lib'
      opts << '-DCMAKE_BUILD_TYPE=Release'
      opts
    end

    def install
      super
      # After `make install`, the .so/.dylib/.dll is under ports/<name>/<ver>/lib/.
      # Copy it into the gem's lib/libpng/ so FFI can load it at runtime.
      libs = Dir.glob(File.join(port_path, 'lib', shared_lib_glob))
      raise "no libpng shared lib produced at #{port_path}/lib" if libs.empty?

      target_dir = ROOT.join('lib', 'libpng')
      FileUtils.mkdir_p(target_dir)
      FileUtils.cp_r(libs, target_dir, verbose: true)

      verify_libs
    end

    def verify_libs
      each_built_lib do |path|
        out, st = Open3.capture2("file #{path}")
        raise "Failed to query file #{path}: #{out}" unless st.exitstatus.zero?

        next if target_format.eql?('skip')

        raise "Invalid file format '#{out}', /#{target_format.source}/ expected" unless target_format.match?(out)

        message("Verifying #{path} ... OK\n")
      end
    end

    def execute(action, command, command_opts = {})
      super(action, command, command_opts.merge(debug: false))
    end

    def message(text)
      return super unless text.start_with?("\rDownloading")

      match = text.match(/(\rDownloading .*)\(\s*\d+%\)/)
      pattern = match ? match[1] : text
      return if @printed[pattern]

      @printed[pattern] = true
      super
    end

    private

    def port_path
      File.join(@target, 'ports', "#{name}-#{version}") # MiniPortile default
    end

    def shared_lib_glob
      if MiniPortile.windows?
        'libpng16*.dll'
      elsif MiniPortile.darwin?
        'libpng16*.dylib'
      else
        'libpng16.so*'
      end
    end

    def each_built_lib(&block)
      Dir.glob(ROOT.join('lib', 'libpng', shared_lib_glob)).each(&block)
    end

    def host_platform
      @host_platform ||=
        case @host
        when /\Ax86_64.*mingw32/
          'x64-mingw32'
        when /\Ax86_64.*linux/
          'x86_64-linux'
        when /\A(arm64|aarch64).*linux/
          'arm64-linux'
        when /\Ax86_64.*(darwin|macos|osx)/
          'x86_64-darwin'
        when /\A(arm64|aarch64).*(darwin|macos|osx)/
          'arm64-darwin'
        else
          @host
        end
    end

    def target_platform
      @target_platform ||=
        case ENV.fetch('target_platform', nil)
        when /\A(arm64|aarch64).*(darwin|macos|osx)/
          'arm64-darwin'
        when /\Ax86_64.*(darwin|macos|osx)/
          'x86_64-darwin'
        when /\A(arm64|aarch64).*linux/
          'aarch64-linux'
        else
          ENV.fetch('target_platform', host_platform)
        end
    end

    def target_format
      @target_format ||=
        case target_platform
        when 'arm64-darwin'
          /Mach-O 64-bit dynamically linked shared library arm64/
        when 'x86_64-darwin'
          /Mach-O 64-bit dynamically linked shared library x86_64/
        when 'aarch64-linux'
          /ELF 64-bit LSB shared object, ARM aarch64/
        when 'x86_64-linux'
          /ELF 64-bit LSB shared object, x86-64/
        when /\Ax64-mingw(32|-ucrt)/
          /PE32\+ executable.*\(DLL\).*x86-64/
        else
          'skip'
        end
    end
  end
end
