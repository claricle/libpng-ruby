# 01 - Architecture

## Goal

Cross-compile `libpng16.so` for `aarch64-linux-ohos` using the official OHOS
NDK (Huawei-blessed toolchain), code-sign it, and empirically verify it in
real OHOS userland (dockerharmony). Replace the 1.6.58.4/.5/.6 approach of
"Alpine-built bytes labeled as OHOS".

## Why this design (vs PR #11 / PR #12)

| Approach | Status | Why rejected |
|---|---|---|
| Alpine bytes labeled OHOS (1.6.58.4/.5) | shipped | unverified assumption; user flagged musl symbol visibility, TLS, pthread layout risks |
| PR #11: hand-written `toolchain.cmake` + system CMake | closed | 5 CI iterations failed (sysroot path, missing zlib in sysroot, try_compile couldn't find crt objects) — root cause: NOT using NDK's bundled `ohos.toolchain.cmake` |
| PR #12: Alpine bytes + dockerharmony verification | closed | still ships Alpine bytes labeled OHOS; user wants proper NDK bytes |
| **PR #13 (this plan)** | current | NDK-bundled `ohos.toolchain.cmake` + static zlib + `binary-sign-tool` + dockerharmony verify |

## Key insights from references

- **OHOS CMake doc** (`openharmony-6.0-app-dev-docs/napi/build-with-ndk-cmake.md`):
  - NDK ships own CMake at `${SDK_PATH}/native/build-tools/cmake/bin/cmake`
  - Toolchain file at `${SDK_PATH}/native/build/cmake/ohos.toolchain.cmake`
  - Invoke: `cmake -DOHOS_ARCH=arm64-v8a -DOHOS_PLATFORM=OHOS -DCMAKE_TOOLCHAIN_FILE=...`
  - Toolchain handles sysroot + `--target=arm-linux-ohos` + try_compile compatibility

- **ohos-node** (`~/src/external/ohos-node/build.sh`):
  - NDK download via `https://dcp.openharmony.cn/api/daily_build/build/list/component`
  - Two components needed: `ohos-sdk-public` (SDK + `binary-sign-tool`) + `LLVM-19` (clang + sysroot)
  - `binary-sign-tool sign -selfSign 1` is mandatory post-build
  - Output runs on OHOS via dockerharmony (real OHOS rootfs)

- **dockerharmony** (`~/src/external/dockerharmony/`):
  - OHOS rootfs (musl + toybox + mksh) in Docker, runs aarch64-linux-musl binaries natively on arm64 hosts
  - OHOS ships zlib as `libshared_libz.z.so` (NOT `libz.so`) — patchelf needed if linking dynamically

- **NDK architecture reality** (verified):
  - `LLVM-19` tarball contains `llvm-linux-x86_64.tar.gz` (x86_64-build clang) + `ohos-sysroot.tar.gz` (architecture-independent sysroot files)
  - There is **no arm64 build of the NDK clang** in the daily_build output
  - `ohos.toolchain.cmake` is a CMake script (architecture-independent)
  - `binary-sign-tool` is in the x86_64-build ohos-sdk

## CI topology (corrected: native arm64 + transparent qemu for NDK binaries)

Single job on `ubuntu-24.04-arm` (native arm64 runner):

1. Install `qemu-user-static` + `binfmt-support` — registers binfmt_misc so
   x86_64 ELF binaries run transparently via `qemu-x86_64`.
2. Run `ext/ohos/setup-ndk.sh` → NDK + LLVM-19 in `ext/ohos/ndk/`
3. `bundle exec rake gem:native:aarch64-linux-ohos` →
   - `OHOS::Recipe#cook` runs:
     - Downloads libpng source (MiniPortile)
     - Builds static zlib via `OHOS::ZlibBuilder` (NDK clang under binfmt)
     - CMake-configures libpng with `ohos.toolchain.cmake` + static zlib (NDK cmake/clang under binfmt)
     - Builds + installs `libpng16.so`
     - Signs `.so` via `OHOS::CodeSigner` (`binary-sign-tool` under binfmt)
4. Run `ext/ohos/verify-prepare.sh` → `ohos-verify/` artifacts (cross-compile smoke-test with NDK clang)
5. Run dockerharmony natively: `docker run --rm -v ...:/work ghcr.io/hqzing/dockerharmony:latest sh -c 'LD_LIBRARY_PATH=. ./smoke-test'`

### Why this is the right topology

| Aspect | x86_64 runner (original plan) | arm64 runner + qemu (revised) |
|---|---|---|
| NDK clang / binary-sign-tool | native speed | ~5x slower (qemu emulation) |
| dockerharmony verification | ~5x slower (qemu binfmt for arm64) | **native speed** |
| CI complexity | needs binfmt setup, multi-arch docker pull | standard docker pull |
| Total CI time | dominated by slow dockerharmony emulation | dominated by slow NDK compile (smaller) |

Compilation is ~1 min native → ~5 min under qemu (acceptable).
dockerharmony smoke-test is ~50ms native → ~250ms under qemu — small absolute number,
but the binfmt setup for arm64 emulation on x86_64 is finicky and has been flaky
in CI historically. Native arm64 docker is rock-solid.

**Net**: arm64 + qemu is simpler AND faster overall.

## MECE file layout

```
ext/ohos/
├── setup-ndk.sh           # Downloads SDK + LLVM-19 (idempotent, shell)
├── smoke-test.c           # Round-trip test (kept from PR #12)
├── verify-prepare.sh      # Cross-compiles smoke-test, bundles for dockerharmony
└── (no toolchain.cmake — we use NDK's bundled ohos.toolchain.cmake)

lib/libpng/
├── recipe.rb              # Add Recipe.for_target factory (OCP seam)
├── ohos.rb                # Module Libpng::OHOS + autoloads
└── ohos/
    ├── ndk.rb             # OHOS::NDK: pure-data path discovery + download
    ├── zlib_builder.rb    # OHOS::ZlibBuilder < MiniPortileCMake (static zlib)
    ├── code_signer.rb     # OHOS::CodeSigner: wraps binary-sign-tool
    └── recipe.rb          # OHOS::Recipe < Libpng::Recipe

lib/libpng.rb              # Add autoload :OHOS, 'libpng/ohos'
ext/extconf.rb             # Use Recipe.for_target(...) factory
```

## OCP compliance

Adding a new cross-compile platform = adding `lib/libpng/<platform>/` with a
`<Platform>::Recipe < Libpng::Recipe` subclass and registering it in
`Recipe.for_target`. No modification of `Libpng::Recipe` needed.

The existing `Libpng::Recipe` is unchanged (except adding the factory class
method). All OHOS logic is in `lib/libpng/ohos/`.
