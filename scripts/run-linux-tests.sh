#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/tests-linux"
TEST_SOURCE="$ROOT/tests/custom_fakelag_tests.cpp"
LAG_SYSTEM_SOURCE="$ROOT/extension/network/LagSystem.cpp"
TEST_BIN="$BUILD_DIR/custom_fakelag_tests"

mkdir -p "$BUILD_DIR"

g++ \
  -std=c++17 \
  -Wall \
  -Wextra \
  -O0 \
  -g \
  -DUNIT_TEST \
  -D_LINUX \
  -DPOSIX \
  -DLINUX \
  -DGNUC \
  -DCOMPILER_GCC \
  -Dstricmp=strcasecmp \
  -D_stricmp=strcasecmp \
  -D_snprintf=snprintf \
  -D_vsnprintf=vsnprintf \
  -DHAVE_STDINT_H \
  -I"$ROOT/extension" \
  -I"$ROOT/.deps/hl2sdk-l4d2/public" \
  -I"$ROOT/.deps/hl2sdk-l4d2/public/tier1" \
  -I"$ROOT/.deps/sourcemod-1.12/public/amtl" \
  -I"$ROOT/.deps/sourcemod-1.12/public" \
  "$TEST_SOURCE" \
  "$LAG_SYSTEM_SOURCE" \
  -o "$TEST_BIN"

"$TEST_BIN"

echo "Tests passed."
