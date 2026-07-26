# CMake toolchain for cross-compiling libpng to OHOS (OpenHarmony /
# Huawei HarmonyOS PC). Used by lib/libpng/recipe.rb when the OHOS
# NDK is available (OHOS_LLVM + OHOS_SYSROOT env vars set by
# ext/ohos/setup-toolchain.sh).
#
# CMAKE_SYSTEM_NAME is set to "Linux" rather than "OHOS" because
# libpng's CMakeLists doesn't know about OHOS and OHOS's ABI is
# musl-linux-compatible at the file-format level. The sysroot provides
# the actual libc / headers; the system name just tells CMake's
# find_library / try_compile machinery to use the cross toolchain.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(OHOS_LLVM "$ENV{OHOS_LLVM}")
set(OHOS_SYSROOT "$ENV{OHOS_SYSROOT}")

set(CMAKE_C_COMPILER "${OHOS_LLVM}/bin/aarch64-unknown-linux-ohos-clang")
set(CMAKE_CXX_COMPILER "${OHOS_LLVM}/bin/aarch64-unknown-linux-ohos-clang++")
set(CMAKE_AR "${OHOS_LLVM}/bin/llvm-ar" CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB "${OHOS_LLVM}/bin/llvm-ranlib" CACHE FILEPATH "Ranlib")

set(CMAKE_SYSROOT "${OHOS_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${OHOS_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
