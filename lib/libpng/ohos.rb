# frozen_string_literal: true

# Libpng::OHOS encapsulates everything OHOS-specific needed to build the
# aarch64-linux-ohos pre-compiled gem. Only loaded when
# Libpng::Recipe.for_target is called with an OHOS target -- the regular
# (source / ruby platform) gem install path never touches this code.
#
# Subclasses are autoloaded from this file so that requiring 'libpng' stays
# cheap (no NDK code is parsed unless OHOS is in play).
module Libpng
  # Encapsulates everything OHOS-specific needed to build the
  # aarch64-linux-ohos pre-compiled gem. Only loaded when
  # Libpng::Recipe.for_target is called with an OHOS target -- the regular
  # (source / ruby platform) gem install path never touches this code.
  #
  # Subclasses are autoloaded from this file so that requiring 'libpng' stays
  # cheap (no NDK code is parsed unless OHOS is in play).
  module OHOS
    autoload :NDK, 'libpng/ohos/ndk'
    autoload :Recipe, 'libpng/ohos/recipe'
    autoload :ZlibBuilder, 'libpng/ohos/zlib_builder'
    autoload :CodeSigner, 'libpng/ohos/code_signer'

    # clang --target value consumed by ohos.toolchain.cmake.
    OHOS_ARCH = 'arm64-v8a'
    OHOS_PLATFORM = 'OHOS'
  end
end
