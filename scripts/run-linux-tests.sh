#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/tests-linux"
TEST_SOURCE="$ROOT/tests/custom_fakelag_tests.cpp"
LAG_SYSTEM_SOURCE="$ROOT/extension/network/LagSystem.cpp"
TEST_BIN="$BUILD_DIR/custom_fakelag_tests"

DEPS_DIR="${DEPS_DIR:-$ROOT/.deps/exts-linux}"
mkdir -p "$BUILD_DIR"
extra_flags=()
if [[ "${SANITIZE:-0}" == 1 ]]; then
  extra_flags=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi

${CXX:-g++} "${extra_flags[@]}" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  -O0 \
  -g \
  -DUNIT_TEST \
  -D_LINUX \
  -DPOSIX \
  -DLINUX \
  -DGNUC \
  -DCOMPILER_GCC \
  -Dstricmp=strcasecmp \
  -D_stricmp=stricmp \
  -D_snprintf=snprintf \
  -D_vsnprintf=vsnprintf \
  -DHAVE_STDINT_H \
  -I"$ROOT/extension" \
  -I"$DEPS_DIR/hl2sdk-l4d2/public" \
  -I"$DEPS_DIR/hl2sdk-l4d2/public/tier1" \
  -I"$DEPS_DIR/sourcemod-1.12/public/amtl" \
  -I"$DEPS_DIR/sourcemod-1.12/public" \
  "$TEST_SOURCE" \
  "$LAG_SYSTEM_SOURCE" \
  "$ROOT/extension/network/LagPacketPolicy.cpp" \
  "$ROOT/extension/latency/PlayerLagManager.cpp" \
  "$ROOT/extension/latency/PlayerProfileService.cpp" \
  -o "$TEST_BIN"

"$TEST_BIN"

echo "Tests passed."
