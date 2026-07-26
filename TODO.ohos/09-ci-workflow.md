# 09 - CI workflow: build.yml + release.yml

## Topology

| Aspect | Value |
|---|---|
| Runner | `ubuntu-24.04-arm` (native arm64) |
| Build container | None (run on host) |
| NDK tool emulation | `qemu-user-static` + binfmt_misc (transparent x86_64 emulation) |
| Verification | dockerharmony (native arm64, no emulation) |

## New OHOS job (replaces the Alpine-container matrix entry in `build_musl`)

```yaml
build_ohos:
  needs: bump   # for release.yml; build.yml omits this
  runs-on: ubuntu-24.04-arm
  steps:
    - uses: actions/checkout@v4

    - uses: ruby/setup-ruby@master
      with:
        ruby-version: '3.3'
        bundler-cache: true

    - name: Install build tools
      run: |
        sudo apt-get update
        sudo apt-get install -y cmake ninja-build zlib1g-dev curl jq unzip \
                                 qemu-user-static binfmt-support

    - name: Register binfmt for x86_64 (NDK binaries are x86_64 ELF)
      run: |
        sudo update-binfmts --enable qemu-x86_64
        # Smoke-check: invoke an x86_64 binary to confirm binfmt is wired up
        docker run --rm --platform linux/amd64 alpine:latest echo "binfmt ok"

    - name: Cache OHOS NDK
      id: cache-ndk
      uses: actions/cache@v4
      with:
        path: ext/ohos/ndk
        key: ohos-ndk-arm64-${{ hashFiles('ext/ohos/setup-ndk.sh') }}

    - name: Setup OHOS NDK (if not cached)
      if: steps.cache-ndk.outputs.cache-hit != 'true'
      run: sh ext/ohos/setup-ndk.sh --prefix ext/ohos/ndk

    - name: Build OHOS gem (libpng + static zlib + signing)
      run: bundle exec rake gem:native:aarch64-linux-ohos
      env:
        target_platform: aarch64-linux-ohos

    - name: Prepare dockerharmony artifacts
      run: |
        NDK_ROOT=$PWD/ext/ohos/ndk sh ext/ohos/verify-prepare.sh

    - name: Verify in dockerharmony (real OHOS userland)
      run: |
        docker pull ghcr.io/hqzing/dockerharmony:latest
        docker run --rm \
          -v "$PWD/ohos-verify:/work" \
          -w /work \
          ghcr.io/hqzing/dockerharmony:latest \
          sh -c 'LD_LIBRARY_PATH=. ./smoke-test'

    - uses: actions/upload-artifact@v4
      with:
        name: pkg-aarch64-linux-ohos
        path: pkg/*.gem
```

## build_musl matrix

Remove the `aarch64-linux-ohos` entry from `build_musl.matrix.include`. OHOS
no longer builds inside the Alpine container. The remaining musl entries
(`x86_64-linux-musl`, `aarch64-linux-musl`) stay as-is.

## Caching notes

- `actions/cache@v4` on `ext/ohos/ndk/` keyed by `setup-ndk.sh` hash.
- NDK is ~1.5GB; cached across runs saves ~3 min per build (download + extract).
- The cache key includes `arm64` to avoid collisions if we ever add x86_64 paths.

## Why binfmt and not explicit qemu invocation

`update-binfmts --enable qemu-x86_64` registers a kernel-level handler. Any
subsequent x86_64 ELF binary is transparently emulated — no need to wrap
each invocation in `qemu-x86_64 ./binary`. The OHOS toolchain, cmake,
clang, and binary-sign-tool all run unmodified.

This matters because `ohos.toolchain.cmake` and MiniPortile internally
invoke `clang` by name. We don't control those subprocess calls; transparent
binfmt lets them work without modification.

## Release.yml specifics

Same job topology as build.yml but:
- `needs: bump`
- Uses `needs.bump.outputs.sha` for checkout ref
- The publish job downloads all platform artifacts including this one
