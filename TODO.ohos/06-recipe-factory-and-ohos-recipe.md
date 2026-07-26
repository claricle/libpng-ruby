# 06 - Recipe factory + OHOS::Recipe

## lib/libpng/recipe.rb modification

Add class-method factory. This is the only change to the existing recipe —
OCP-compliant (open for extension via subclass, closed for modification).

```ruby
class Recipe
  class << self
    def for_target(platform)
      case platform
      when /\A(aarch64|arm64).*linux-ohos\z/
        require 'libpng'  # ensure autoload :OHOS is registered
        Libpng::OHOS::Recipe
      else
        Recipe
      end
    end
  end
end
```

Wait — `require 'libpng'` would cause circular require in some contexts. Let
me think... Actually, by the time `for_target` is called, `lib/libpng.rb` has
already been loaded (it's how `Libpng::Recipe` got loaded in the first place).
So the autoload machinery is already set up. The case statement just returns
the class reference; Ruby's autoload handles the actual file load.

Better:

```ruby
def self.for_target(platform)
  return Recipe unless platform&.end_with?('-ohos')

  Libpng::OHOS::Recipe  # autoload triggers here
end
```

## ext/extconf.rb modification

```ruby
target = ENV.fetch('target_platform', nil)
recipe = Libpng::Recipe.for_target(target).new
recipe.cook_if_not
```

Existing `Recipe.new` callers (no target_platform) get `Recipe` — unchanged behavior.

## lib/libpng/ohos/recipe.rb

```ruby
class Recipe < ::Libpng::Recipe
  def initialize
    super
    @ndk = OHOS::NDK.new(root: ext_path('ndk'))
    @zlib = OHOS::ZlibBuilder.new(ndk: @ndk)
  end

  def cook
    @ndk.download unless @ndk.exist?
    @zlib.cook_if_not
    super
  end

  def configure_defaults
    super +
      ohos_toolchain_flags +
      zlib_flags +
      release_flags
  end

  def install
    super
    OHOS::CodeSigner.new(@ndk).sign(built_so_path)
  end

  private

  def ohos_toolchain_flags
    [
      "-DCMAKE_TOOLCHAIN_FILE=#{@ndk.toolchain_path}",
      "-DOHOS_ARCH=#{OHOS::OHOS_ARCH}",
      '-DOHOS_PLATFORM=OHOS',
      "-DCMAKE_SYSROOT=#{@ndk.sysroot_path}"
    ]
  end

  def zlib_flags
    [
      "-DZLIB_LIBRARY=#{@zlib.libz_path}",
      "-DZLIB_INCLUDE_DIR=#{@zlib.include_path}"
    ]
  end

  def release_flags
    ['-DCMAKE_BUILD_TYPE=Release']
  end

  def built_so_path
    ROOT.join('lib', 'libpng', 'libpng16.so')
  end

  def ext_path(*parts)
    ROOT.join('ext', 'ohos', *parts)
  end
end
```

## Notes on existing recipe overrides

`OHOS::Recipe` inherits:
- `target_platform` returns `'aarch64-linux-ohos'` (already correct in base recipe's case statement)
- `cpu_type` returns `'aarch64'` (already correct)
- `cmake_system_name` returns `'Linux'` (already correct)
- `target_format` returns the ELF regex (already correct)

So we only override `cook`, `configure_defaults`, `install`. Base recipe handles the rest.

## Testability

Spec verifies:
- `Recipe.for_target('aarch64-linux-ohos')` returns `OHOS::Recipe`.
- `Recipe.for_target(nil)` returns `Recipe`.
- `Recipe.for_target('x86_64-linux')` returns `Recipe`.
- `OHOS::Recipe#configure_defaults` includes CMAKE_TOOLCHAIN_FILE and ZLIB_LIBRARY.
