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
MMSOURCE_DIR="${MMSOURCE_DIR:-$DEPS_DIR/mmsource-1.12}"
HL2SDK_DIR="${HL2SDK_DIR:-$DEPS_DIR/hl2sdk-l4d2}"
VENV_DIR="${VENV_DIR:-$DEPS_DIR/.venv-linux}"
CONFIGURE_SCRIPT="${CONFIGURE_SCRIPT:-$ROOT_DIR/configure.py}"
MANIFEST_PATH="${MANIFEST_PATH:-$ROOT_DIR/plugin-package-map.json}"

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

readarray -t BUILD_EXTENSION_RECORDS < <("$VENV_PYTHON" - "$MANIFEST_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    manifest = json.load(f)

for bucket, extensions in manifest.get('build', {}).get('extensions', {}).items():
    for extension in extensions:
        print(f"{bucket}|{extension}")
PY
)

if [[ "${#BUILD_EXTENSION_RECORDS[@]}" -ne 1 ]]; then
  echo "Expected exactly one extension in build.extensions, found ${#BUILD_EXTENSION_RECORDS[@]}." >&2
  exit 1
fi

IFS='|' read -r EXTENSION_BUCKET EXTENSION_STEM <<< "${BUILD_EXTENSION_RECORDS[0]}"

for required_dir in "$HL2SDK_DIR" "$SOURCEMOD_DIR" "$MMSOURCE_DIR"; do
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
CANONICAL_EXT_DIR="$PACKAGE_DIR"
if [[ "$EXTENSION_BUCKET" != "root" ]]; then
  CANONICAL_EXT_DIR="$PACKAGE_DIR/$EXTENSION_BUCKET"
  mkdir -p "$CANONICAL_EXT_DIR"
fi
CANONICAL_EXT_BIN="$CANONICAL_EXT_DIR/$EXTENSION_STEM.ext.so"
EXT_BIN="$(find "$PACKAGE_DIR" -maxdepth 1 -type f -name "$EXTENSION_STEM.ext*.so" | head -n 1)"

if [[ -z "$EXT_BIN" || ! -f "$EXT_BIN" ]]; then
  echo "Build completed but no $EXTENSION_STEM extension binary was found in $PACKAGE_DIR." >&2
  exit 1
fi

if [[ "$EXT_BIN" != "$CANONICAL_EXT_BIN" ]]; then
  mv "$EXT_BIN" "$CANONICAL_EXT_BIN"
  EXT_BIN="$CANONICAL_EXT_BIN"
fi

cat <<EOF
Build complete.
BUILD_DIR=$BUILD_DIR
EXTENSION=$EXT_BIN
EOF
