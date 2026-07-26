# 07 - lib/libpng/ohos/code_signer.rb

## Purpose

Run `binary-sign-tool sign -selfSign 1` on the freshly built `libpng16.so`.
Required for runtime loading on real OHOS hardware (dockerharmony skips this
check, but production devices enforce it).

## Class

```ruby
class CodeSigner
  def initialize(ndk)
    @ndk = ndk
  end

  # Returns the argv that #sign would run. Pure data — testable without
  # actually invoking the tool.
  def sign_command(so_path)
    [
      @ndk.sign_tool_path.to_s,
      'sign',
      '-selfSign', '1',
      '-inFile', so_path.to_s,
      '-outFile', so_path.to_s
    ]
  end

  # Runs binary-sign-tool. Returns true on success, false otherwise.
  # Caller (OHOS::Recipe#install) raises on false.
  def sign(so_path)
    system(*sign_command(so_path))
  end
end
```

## Design notes

- No `instance_variable_get`/`set`.
- `@ndk` is the only ivar; set in constructor, read in methods.
- `#sign_command` is pure (returns data, no side effects) — fully spec-able.
- `#sign` wraps it in `system()`. Production-only; not specced.
- This follows the "extract pure-data method from side-effecting method" pattern,
  making the class testable without doubles (per project rule: no doubles).

## Testability

Spec verifies `#sign_command` shape:
- First element is the path to `binary-sign-tool`.
- Contains `'sign'`, `'-selfSign'`, `'1'`, `'-inFile'`, `'-outFile'`.
- inFile and outFile are the same path (in-place signing).

Constructs a real `OHOS::NDK` instance pointing at a fake dir structure.
