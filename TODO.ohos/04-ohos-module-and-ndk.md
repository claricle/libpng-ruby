# 04 - lib/libpng/ohos.rb + lib/libpng/ohos/ndk.rb

## lib/libpng.rb modification

Add one autoload entry (follows existing convention):

```ruby
# OHOS cross-compile support. Only loaded when building for aarch64-linux-ohos.
autoload :OHOS, 'libpng/ohos'
```

## lib/libpng/ohos.rb

Module namespace + sub-autoloads. Loaded lazily only when OHOS is referenced
(i.e., when `Recipe.for_target('aarch64-linux-ohos')` is called).

```ruby
# frozen_string_literal: true

module Libpng
  module OHOS
    autoload :NDK, 'libpng/ohos/ndk'
    autoload :Recipe, 'libpng/ohos/recipe'
    autoload :ZlibBuilder, 'libpng/ohos/zlib_builder'
    autoload :CodeSigner, 'libpng/ohos/code_signer'

    TARGET_TRIPLE = 'aarch64-linux-ohos'
    OHOS_ARCH = 'arm64-v8a'
  end
end
```

## lib/libpng/ohos/ndk.rb

Pure-data class — discovers and validates NDK paths. No shell calls except
via explicit `#download` (which invokes `setup-ndk.sh`).

### Public API

```ruby
class NDK
  def initialize(root:)                 # root = Pathname to NDK install dir
  def exist?                            # true if all expected paths present
  def toolchain_path                    # Pathname to ohos.toolchain.cmake
  def clang_path                        # Pathname to aarch64-unknown-linux-ohos-clang
  def sysroot_path                      # Pathname to OHOS sysroot root
  def sign_tool_path                    # Pathname to binary-sign-tool
  def cmake_path                        # Pathname to NDK's bundled cmake binary
  def download                          # invoke setup-ndk.sh (no-op if exist?)
end
```

### Design notes

- All path accessors return `Pathname` (not String) for composability.
- `#exist?` checks the four critical paths (toolchain, clang, sysroot, sign-tool).
- `#download` invokes `ext/ohos/setup-ndk.sh` via `system()`. Idempotent.
- No `instance_variable_get`/`set` — ivars are private, accessed via methods.
- No `respond_to?` — type checks use `is_a?`.

### Testability

Spec constructs a fake NDK directory structure (just empty files at expected
paths) and verifies accessors return correct Pathnames. No doubles, no real
download.
