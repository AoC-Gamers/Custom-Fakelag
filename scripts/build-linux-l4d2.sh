#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

load_dotenv() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

    local name="${line%%=*}"
    local value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    if [[ -z "${!name+x}" ]]; then
      export "$name=$value"
    fi
  done < "$env_file"
}

load_dotenv "$ENV_FILE"

DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.deps}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.build/linux-l4d2}"
SOURCEMOD_DIR="${SOURCEMOD_DIR:-$DEPS_DIR/sourcemod-1.12}"
SOURCEMOD_PACKAGE_DIR="${SOURCEMOD_PACKAGE_DIR:-$DEPS_DIR/sourcemod-package}"
MMSOURCE_DIR="${MMSOURCE_DIR:-$DEPS_DIR/mmsource-1.12}"
HL2SDK_DIR="${HL2SDK_DIR:-$DEPS_DIR/hl2sdk-l4d2}"
VENV_DIR="${VENV_DIR:-$DEPS_DIR/.venv-linux}"
CONFIGURE_SCRIPT="${CONFIGURE_SCRIPT:-$ROOT_DIR/configure.py}"
PLAYER_FAKELAG_SOURCE="${PLAYER_FAKELAG_SOURCE:-$ROOT_DIR/scripting/player_fakelag.sp}"

case "$(uname -s)" in
  Linux)
    ;;
  *)
    echo "This build script targets Linux L4D2 extensions and must be run on Linux." >&2
    echo "Use make deps on any platform, but run make build inside a Linux environment with 32-bit toolchain support." >&2
    exit 1
    ;;
esac

venv_python() {
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    printf '%s\n' "$VENV_DIR/bin/python"
    return
  fi

  if [[ -x "$VENV_DIR/Scripts/python.exe" ]]; then
    printf '%s\n' "$VENV_DIR/Scripts/python.exe"
    return
  fi

  return 1
}

venv_ambuild() {
  if [[ -x "$VENV_DIR/bin/ambuild" ]]; then
    printf '%s\n' "$VENV_DIR/bin/ambuild"
    return
  fi

  if [[ -x "$VENV_DIR/Scripts/ambuild.exe" ]]; then
    printf '%s\n' "$VENV_DIR/Scripts/ambuild.exe"
    return
  fi

  if [[ -x "$VENV_DIR/Scripts/ambuild" ]]; then
    printf '%s\n' "$VENV_DIR/Scripts/ambuild"
    return
  fi

  return 1
}

if ! VENV_PYTHON="$(venv_python)"; then
  echo "Missing Python venv at $VENV_DIR. Run scripts/fetch-linux-deps.sh first." >&2
  exit 1
fi

if ! VENV_AMBUILD="$(venv_ambuild)"; then
  echo "Missing AMBuild in $VENV_DIR. Run scripts/fetch-linux-deps.sh first." >&2
  exit 1
fi

for required_dir in "$HL2SDK_DIR" "$SOURCEMOD_DIR" "$SOURCEMOD_PACKAGE_DIR" "$MMSOURCE_DIR"; do
  if [[ ! -d "$required_dir" ]]; then
    echo "Missing required directory: $required_dir" >&2
    exit 1
  fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

pushd "$BUILD_DIR" > /dev/null
"$VENV_PYTHON" "$CONFIGURE_SCRIPT" \
  --sdks l4d2 \
  --hl2sdk-root "$DEPS_DIR" \
  --mms-path "$MMSOURCE_DIR" \
  --sm-path "$SOURCEMOD_DIR" \
  --enable-optimize

if [[ ! -f "$BUILD_DIR/.ambuild2/vars" ]]; then
  echo "AMBuild configure did not produce $BUILD_DIR/.ambuild2/vars." >&2
  echo "Check the configure output above for the real error." >&2
  exit 1
fi

"$VENV_AMBUILD"
popd > /dev/null

PACKAGE_DIR="$BUILD_DIR/package/addons/sourcemod/extensions"
CANONICAL_EXT_BIN="$PACKAGE_DIR/custom_fakelag.ext.so"
EXT_BIN="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name 'custom_fakelag.ext*.so' | head -n 1)"

if [[ -z "$EXT_BIN" || ! -f "$EXT_BIN" ]]; then
  echo "Build completed but no custom_fakelag extension binary was found in $PACKAGE_DIR." >&2
  exit 1
fi

if [[ "$EXT_BIN" != "$CANONICAL_EXT_BIN" ]]; then
  cp "$EXT_BIN" "$CANONICAL_EXT_BIN"
  EXT_BIN="$CANONICAL_EXT_BIN"
fi

SPCOMP="$SOURCEMOD_PACKAGE_DIR/addons/sourcemod/scripting/spcomp"
SP_INCLUDE_DIR="$SOURCEMOD_PACKAGE_DIR/addons/sourcemod/scripting/include"
PLUGIN_INCLUDE_DIR="$ROOT_DIR/scripting/include"
PLUGIN_OUTPUT_DIR="$BUILD_DIR/package/addons/sourcemod/plugins"
PLAYER_FAKELAG_BINARY="$PLUGIN_OUTPUT_DIR/player_fakelag.smx"

if [[ ! -x "$SPCOMP" ]]; then
  echo "Missing spcomp compiler at $SPCOMP." >&2
  exit 1
fi

mkdir -p "$PLUGIN_OUTPUT_DIR"
"$SPCOMP" "$PLAYER_FAKELAG_SOURCE" -o"$PLAYER_FAKELAG_BINARY" -i"$PLUGIN_INCLUDE_DIR" -i"$SP_INCLUDE_DIR"

cat <<EOF
Build complete.
BUILD_DIR=$BUILD_DIR
EXTENSION=$EXT_BIN
PLUGIN=$PLAYER_FAKELAG_BINARY
EOF
