# 10 - Specs

## Spec files

```
spec/ohos/
├── ndk_spec.rb
├── zlib_builder_spec.rb
├── code_signer_spec.rb
└── recipe_spec.rb

spec/recipe_factory_spec.rb   # Libpng::Recipe.for_target
```

## Rules (per CLAUDE.md)

- No `double()`. Use real instances.
- No `send` to private methods.
- No `instance_variable_set`/`get`.
- No `respond_to?` for type checks.

## Specs

### spec/recipe_factory_spec.rb

```ruby
require 'spec_helper'

RSpec.describe Libpng::Recipe, '.for_target' do
  it 'returns OHOS::Recipe for aarch64-linux-ohos' do
    expect(described_class.for_target('aarch64-linux-ohos')).to be(Libpng::OHOS::Recipe)
  end

  it 'returns Recipe for nil (host build, source gem)' do
    expect(described_class.for_target(nil)).to be(Libpng::Recipe)
  end

  it 'returns Recipe for non-OHOS targets' do
    expect(described_class.for_target('x86_64-linux')).to be(Libpng::Recipe)
    expect(described_class.for_target('aarch64-linux-musl')).to be(Libpng::Recipe)
  end
end
```

### spec/ohos/ndk_spec.rb

Uses a fake NDK directory structure (Dir.mktmpdir + touch empty files at
expected paths). Verifies accessors return correct Pathnames.

```ruby
RSpec.describe Libpng::OHOS::NDK do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:ndk) { described_class.new(root: root) }

  before do
    # Create the expected file layout
    root.join('ohos-sdk/linux/build/cmake/ohos.toolchain.cmake').mkpath_p.tap { |p| FileUtils.touch(p) }
    root.join('llvm-19/llvm/bin/aarch64-unknown-linux-ohos-clang').mkpath_p.tap { |p| FileUtils.touch(p) }
    root.join('llvm-19/sysroot/usr/lib/aarch64-linux-oho').mkpath  # dir exists check
    root.join('ohos-sdk/linux/toolchains/lib/binary-sign-tool').mkpath_p.tap { |p| FileUtils.touch(p) }
  end

  describe '#exist?' do
    it 'returns true when all critical paths exist' do
      expect(ndk.exist?).to be true
    end
  end

  describe '#toolchain_path' do
    it 'points at ohos.toolchain.cmake' do
      expect(ndk.toolchain_path).to end_with('build/cmake/ohos.toolchain.cmake')
    end
  end

  # ... similar for clang_path, sysroot_path, sign_tool_path
end
```

### spec/ohos/code_signer_spec.rb

```ruby
RSpec.describe Libpng::OHOS::CodeSigner do
  let(:ndk) { instance_of_real_ndk_with_fake_paths }  # use the same helper as ndk_spec
  let(:signer) { described_class.new(ndk) }
  let(:so_path) { Pathname.new('/tmp/libpng16.so') }

  describe '#sign_command' do
    subject(:cmd) { signer.sign_command(so_path) }

    it 'starts with binary-sign-tool path' do
      expect(cmd.first).to end_with('binary-sign-tool')
    end

    it 'passes sign subcommand' do
      expect(cmd).to include('sign')
    end

    it 'passes selfSign=1' do
      expect(cmd).to include('-selfSign', '1')
    end

    it 'signs in-place (inFile == outFile)' do
      in_idx = cmd.index('-inFile')
      out_idx = cmd.index('-outFile')
      expect(cmd[in_idx + 1]).to eq(so_path.to_s)
      expect(cmd[out_idx + 1]).to eq(so_path.to_s)
    end
  end
end
```

### spec/ohos/zlib_builder_spec.rb

```ruby
RSpec.describe Libpng::OHOS::ZlibBuilder do
  let(:ndk) { fake_ndk_instance }
  let(:builder) { described_class.new(ndk: ndk) }

  describe 'ZLIB_URL' do
    it 'matches the pinned version' do
      expect(described_class::ZLIB_URL).to include(described_class::ZLIB_VERSION)
    end
  end

  describe '#configure_defaults' do
    it 'includes the OHOS toolchain file' do
      flags = builder.configure_defaults.join(' ')
      expect(flags).to match(%r{CMAKE_TOOLCHAIN_FILE=.*ohos\.toolchain\.cmake})
    end

    it 'requests static build' do
      flags = builder.configure_defaults.join(' ')
      expect(flags).to include('BUILD_SHARED_LIBS=OFF')
    end
  end

  describe '#libz_path' do
    it 'points at lib/libz.a' do
      expect(builder.libz_path.to_s).to end_with('lib/libz.a')
    end
  end
end
```

### spec/ohos/recipe_spec.rb

```ruby
RSpec.describe Libpng::OHOS::Recipe do
  describe '#configure_defaults' do
    subject(:flags) { described_class.new.configure_defaults.join(' ') }

    it 'includes OHOS toolchain file' do
      expect(flags).to match(%r{CMAKE_TOOLCHAIN_FILE=.*ohos\.toolchain\.cmake})
    end

    it 'includes static zlib path' do
      expect(flags).to include('ZLIB_LIBRARY=')
      expect(flags).to match(/ZLIB_LIBRARY=.*libz\.a/)
    end

    it 'sets OHOS_ARCH=arm64-v8a' do
      expect(flags).to include('OHOS_ARCH=arm64-v8a')
    end
  end
end
```

NOTE: These specs don't actually run the build (which requires NDK + network).
They verify the *shape* of the configuration — that the right flags are passed.
Integration is verified by CI.
