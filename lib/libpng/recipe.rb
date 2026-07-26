require 'rbconfig'
require 'mini_portile2'
require 'pathname'
require 'tmpdir'
require 'open3'

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
    LIBPNG_SHA256 = '8c9b05b675ca7301a458df2c2e46f26e1d41ff36b8863f8c33530bc58c2e6225'.freeze

    ROOT = Pathname.new(File.expand_path('../..', __dir__))

    def initialize
      super('libpng', Libpng::LIBPNG_VERSION)

      @files << {
        url: LIBPNG_URL,
        sha256: LIBPNG_SHA256
      }

      @target = ROOT.join(@target).to_s
      @printed = {}
      setup_cross_compile if cross_compile?
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
      # After `make install`, the shared lib lives under ports/<name>/<ver>/.
      # On Linux/macOS that's lib/. On Windows, CMake's GNUInstallDirs puts
      # the .dll in bin/ and the import library (.dll.a) in lib/ — we only
      # ship the .dll, so search both.
      libs = Dir.glob(File.join(port_path, shared_lib_install_glob))
      raise "no libpng shared lib produced under #{port_path}" if libs.empty?

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

    # Glob (with port_path prefix) for the freshly installed shared lib.
    # On Windows the .dll installs to bin/; on Unix-likes it stays in lib/.
    def shared_lib_install_glob
      if MiniPortile.windows?
        '{bin,lib}/libpng16*.dll'
      else
        "lib/#{shared_lib_glob}"
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
        when /\A(aarch64|arm64).*mingw/
          'aarch64-mingw-ucrt'
        when /\Ax86_64.*linux-musl/
          'x86_64-linux-musl'
        when /\A(aarch64|arm64).*linux-musl/
          'aarch64-linux-musl'
        when /\Ax86_64.*linux/
          'x86_64-linux'
        when /\A(aarch64|arm64).*linux/
          'aarch64-linux'
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
        when /\A(arm64|aarch64).*linux-musl/
          'aarch64-linux-musl'
        when /\A(arm64|aarch64).*linux/
          'aarch64-linux'
        when /\Ax86_64.*linux-musl/
          'x86_64-linux-musl'
        else
          ENV.fetch('target_platform', host_platform)
        end
    end

    def cross_compile?
      target_platform != host_platform
    end

    # Configure MiniPortile + CMake for cross-compilation. Native builds
    # (host_platform == target_platform) skip this entirely.
    def setup_cross_compile
      # All targeted platforms now have native runners (ubuntu-24.04-arm for
      # aarch64-linux, windows-11-arm for aarch64-mingw-ucrt, Alpine containers
      # for the musl variants). This hook is kept as a seam for future
      # cross-compile targets (e.g. aarch64-linux on an x86_64 host).
    end

    def cpu_type
      case target_platform
      when 'aarch64-linux', 'aarch64-linux-musl', 'arm64-darwin', 'aarch64-mingw-ucrt' then 'aarch64'
      when 'x86_64-linux', 'x86_64-linux-musl', 'x86_64-darwin', /\Ax64-mingw/ then 'x86_64'
      else
        super
      end
    end

    def cmake_system_name
      case target_platform
      when 'aarch64-linux', 'x86_64-linux', 'aarch64-linux-musl', 'x86_64-linux-musl' then 'Linux'
      when 'arm64-darwin', 'x86_64-darwin' then 'Darwin'
      when /\A(aarch64-)?mingw/, /\Ax64-mingw/ then 'Windows'
      else
        super
      end
    end

    def target_format
      @target_format ||=
        case target_platform
        when 'arm64-darwin'
          /Mach-O 64-bit dynamically linked shared library arm64/
        when 'x86_64-darwin'
          /Mach-O 64-bit dynamically linked shared library x86_64/
        when 'aarch64-linux', 'aarch64-linux-musl'
          /ELF 64-bit LSB shared object, ARM aarch64/
        when 'x86_64-linux', 'x86_64-linux-musl'
          /ELF 64-bit LSB shared object, x86-64/
        when 'aarch64-mingw-ucrt'
          /PE32\+ executable.*\(DLL\).*ARM64/
        when /\Ax64-mingw(32|-ucrt)/
          /PE32\+ executable.*\(DLL\).*x86-64/
        else
          'skip'
        end
    end
  end
end
