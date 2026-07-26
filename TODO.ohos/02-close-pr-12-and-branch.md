# 02 - Close PR #12, branch off main

## Steps

1. Close PR #12 with a comment explaining the pivot:

   > Closing in favor of a proper OHOS NDK cross-compile approach (PR #13).
   > The dockerharmony verification step is reused; the build approach changes
   > from "Alpine-built bytes labeled OHOS" to "NDK-built bytes signed with
   > binary-sign-tool". The smoke-test.c file is carried over.

2. From `main`, create `fix/ohos-ndk-cmake`:
   ```sh
   git checkout main
   git pull origin main
   git checkout -b fix/ohos-ndk-cmake
   ```

3. Cherry-pick reusable files from `fix/ohos-dockerharmony`:
   - `ext/ohos/smoke-test.c` — keep as-is
   - `lib/libpng/version.rb` — keep iteration = 6 (it's already at 6 on PR #12 branch)

   `verify-prepare.sh` will be rewritten (was Alpine-gcc-based; new version
   uses NDK clang for cross-compile from x86_64 host).

## Why branch off main (not off fix/ohos-dockerharmony)

PR #12's CI changes (build.yml, release.yml) are incompatible with the NDK
approach — they assume Alpine container build. Cleaner to start fresh and
re-introduce only what's needed.
