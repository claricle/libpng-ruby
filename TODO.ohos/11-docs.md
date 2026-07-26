# 11 - Docs: README + CHANGELOG + CLAUDE.md

## README.adoc

Update OHOS row in the platforms table:

```asciidoc
| `aarch64-linux-ohos` | ARM64 OpenHarmony / Huawei HarmonyOS PC | `ubuntu-latest` (x86_64), cross-compiled with OHOS NDK, **verified in dockerharmony** (real OHOS userland)
```

Add a new section after "Pre-compiled platform gems" explaining the OHOS build
path briefly (NDK + toolchain file + static zlib + binary-sign-tool).

## CHANGELOG.md

Replace the 1.6.58.6 entry (currently describes dockerharmony verification
of Alpine bytes) with a new entry describing the NDK cross-compile:

```markdown
## [1.6.58.6] - 2026-07-26

### Changed
- **OHOS (`aarch64-linux-ohos`) is now cross-compiled with the official OHOS
  NDK** (Huawei's `ohos.toolchain.cmake` + LLVM-19 clang), replacing the
  1.6.58.4/.5 approach of shipping Alpine-built musl bytes labeled as OHOS.

  The build runs on `ubuntu-latest` (x86_64). The OHOS NDK clang cross-compiles
  to `aarch64-linux-ohos`; zlib is built statically with the same toolchain
  and linked into `libpng16.so` (avoids the OHOS non-standard zlib SONAME).
  The freshly built `.so` is code-signed with `binary-sign-tool sign -selfSign 1`
  (mandatory for runtime loading on production OHOS devices).

  Verification: the signed `.so` is loaded by a smoke-test binary inside
  real OHOS userland (the `dockerharmony` container running via qemu binfmt
  on the x86_64 runner). Build fails if the smoke test fails.

### Added
- `lib/libpng/ohos.rb`, `lib/libpng/ohos/{ndk,zlib_builder,code_signer,recipe}.rb`
  — OHOS cross-compile support. Lazy-loaded only when building for OHOS.
- `ext/ohos/setup-ndk.sh` — downloads OHOS SDK + LLVM-19 via daily_build API.
- `ext/ohos/smoke-test.c` — minimal libpng round-trip test for dockerharmony.
- `ext/ohos/verify-prepare.sh` — cross-compiles smoke-test with NDK clang,
  bundles signed `.so` + SONAME symlinks.
- `Recipe.for_target(platform)` factory — OCP seam for platform-specific recipes.

### Caveats
- The 1.6.58.4/.5 OHOS gems shipped Alpine-built bytes WITHOUT NDK verification.
  This version is the first with proper OHOS NDK cross-compilation + signing.
- Code signing uses `-selfSign 1` (self-signed, not enrolled with Huawei's
  signing service). Sufficient for OHOS userland load. Production deployment
  on Huawei-managed hardware may require re-signing with an enrolled cert.

### Fixed
- PR #12's verify-prepare.sh had a symlink bug (only copied `libpng16.so`,
  not the SONAME form `libpng16.so.16`). Fixed by copying all three forms.
```

## CLAUDE.md

Update the file table to include the new OHOS files:

```markdown
| `lib/libpng/ohos.rb` | `Libpng::OHOS` namespace + autoloads |
| `lib/libpng/ohos/ndk.rb` | `OHOS::NDK` — discovers/validates NDK paths |
| `lib/libpng/ohos/zlib_builder.rb` | `OHOS::ZlibBuilder < MiniPortileCMake` — static zlib for OHOS |
| `lib/libpng/ohos/code_signer.rb` | `OHOS::CodeSigner` — wraps `binary-sign-tool sign -selfSign 1` |
| `lib/libpng/ohos/recipe.rb` | `OHOS::Recipe < Libpng::Recipe` — OHOS-specific build path |
| `ext/ohos/setup-ndk.sh` | Downloads OHOS SDK + LLVM-19 via daily_build API |
| `ext/ohos/smoke-test.c` | Round-trip test run in dockerharmony |
| `ext/ohos/verify-prepare.sh` | Cross-compiles smoke-test, bundles artifacts |
```

Add an "OHOS build" subsection under "Common commands" explaining the env var:

```markdown
### Building for OHOS

```sh
target_platform=aarch64-linux-ohos bundle exec rake compile    # just build .so
bundle exec rake gem:native:aarch64-linux-ohos                 # full gem
```

The first run downloads the OHOS NDK (~1.5GB) into `ext/ohos/ndk/`. Cached
across runs.
```

## lib/libpng/version.rb

Already at `LIBPNG_RUBY_ITERATION = 6` on the PR #12 branch. The new branch
starts from main, where it's at `5`. Bump to `6` (same target version as PR #12,
just a different .so source).
