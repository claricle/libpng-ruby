# 03 - ext/ohos/setup-ndk.sh

## Purpose

Download and extract the OHOS NDK (SDK + LLVM-19) into `ext/ohos/ndk/`.
Idempotent — skips if the destination already looks complete.

## Source pattern

Adapted from `~/src/external/ohos-node/build.sh` (lines 14-49). Key pieces:

```sh
query_component() {
  component=$1
  curl -fsSL 'https://dcp.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'${component}'","type":1,"startTime":"2025080100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}
```

Two components needed:
- `ohos-sdk-public` → contains `toolchains/lib/binary-sign-tool` + `build/cmake/ohos.toolchain.cmake`
- `LLVM-19` → contains `llvm/bin/aarch64-unknown-linux-ohos-clang` + `ohos-sysroot.tar.gz`

## Script contract

```
Usage: setup-ndk.sh [--prefix <dir>]
Default prefix: $PWD/ext/ohos/ndk

Outputs:
  $PREFIX/ohos-sdk/linux/        # SDK
  $PREFIX/llvm-19/llvm/          # Clang
  $PREFIX/llvm-19/sysroot/       # OHOS sysroot (extracted from ohos-sysroot.tar.gz)

Exits 0 if setup is complete (or was already complete).
```

## Idempotency

Skip download if `$PREFIX/ohos-sdk/linux/toolchains/lib/binary-sign-tool` exists
AND `$PREFIX/llvm-19/sysroot/usr/lib/aarch64-linux-ohos/` exists. This lets
CI cache the directory across runs.

## Dependencies (CI-side)

- `curl`, `tar`, `unzip`, `jq` — apt-installed in workflow before script runs.

## Why shell (not Ruby)

- curl + jq + tar pipeline is 5 lines of shell vs 50+ lines of Ruby (Net::HTTP + JSON parsing).
- Pattern is proven by ohos-node; we follow it verbatim.
- Ruby's role is orchestration (deciding *when* to invoke); the script does the heavy lifting.
