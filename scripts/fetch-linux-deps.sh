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
HL2SDK_DIR="${HL2SDK_DIR:-$DEPS_DIR/hl2sdk-l4d2}"
SOURCEMOD_DIR="${SOURCEMOD_DIR:-$DEPS_DIR/sourcemod-1.12}"
SOURCEMOD_PACKAGE_DIR="${SOURCEMOD_PACKAGE_DIR:-$DEPS_DIR/sourcemod-package}"
MMSOURCE_DIR="${MMSOURCE_DIR:-$DEPS_DIR/mmsource-1.12}"
AMBUILD_DIR="${AMBUILD_DIR:-$DEPS_DIR/ambuild}"
SOURCEMOD_LATEST_LINUX_URL="${SOURCEMOD_LATEST_LINUX_URL:-https://sm.alliedmods.net/smdrop/1.12/sourcemod-latest-linux}"

case "$(uname -s)" in
  Linux)
    DEFAULT_VENV_DIR="$DEPS_DIR/.venv-linux"
    ;;
  *)
    DEFAULT_VENV_DIR="$DEPS_DIR/.venv-windows"
    ;;
esac
VENV_DIR="${VENV_DIR:-$DEFAULT_VENV_DIR}"

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

clone_or_update() {
  local repo_url="$1"
  local repo_dir="$2"
  local branch="$3"

  if [[ -d "$repo_dir/.git" ]]; then
    git -C "$repo_dir" fetch --all --tags --prune
    git -C "$repo_dir" checkout "$branch"
    git -C "$repo_dir" pull --ff-only
    return
  fi

  git clone --branch "$branch" --single-branch "$repo_url" "$repo_dir"
}

sync_submodules_if_present() {
  local repo_dir="$1"

  if [[ ! -f "$repo_dir/.gitmodules" ]]; then
    return
  fi

  git -C "$repo_dir" submodule sync --recursive
  git -C "$repo_dir" submodule update --init --recursive
}

mkdir -p "$DEPS_DIR"

clone_or_update "https://github.com/alliedmodders/hl2sdk.git" "$HL2SDK_DIR" "l4d2"
clone_or_update "https://github.com/alliedmodders/sourcemod.git" "$SOURCEMOD_DIR" "1.12-dev"
clone_or_update "https://github.com/alliedmodders/metamod-source.git" "$MMSOURCE_DIR" "1.12-dev"
clone_or_update "https://github.com/alliedmodders/ambuild.git" "$AMBUILD_DIR" "master"

sync_submodules_if_present "$SOURCEMOD_DIR"
sync_submodules_if_present "$MMSOURCE_DIR"

rm -rf "$SOURCEMOD_PACKAGE_DIR"
mkdir -p "$SOURCEMOD_PACKAGE_DIR"
SOURCEMOD_PACKAGE_NAME="$(curl -fsSL "$SOURCEMOD_LATEST_LINUX_URL")"
SOURCEMOD_PACKAGE_URL="https://sm.alliedmods.net/smdrop/1.12/$SOURCEMOD_PACKAGE_NAME"
curl -fsSL "$SOURCEMOD_PACKAGE_URL" | tar -xz -C "$SOURCEMOD_PACKAGE_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

VENV_PYTHON="$(venv_python)"
"$VENV_PYTHON" -m pip install --upgrade pip
"$VENV_PYTHON" -m pip install "$AMBUILD_DIR"

cat <<EOF
Dependencies ready.
ROOT_DIR=$ROOT_DIR
DEPS_DIR=$DEPS_DIR
HL2SDK_DIR=$HL2SDK_DIR
SOURCEMOD_DIR=$SOURCEMOD_DIR
SOURCEMOD_PACKAGE_DIR=$SOURCEMOD_PACKAGE_DIR
MMSOURCE_DIR=$MMSOURCE_DIR
AMBUILD_DIR=$AMBUILD_DIR
VENV_DIR=$VENV_DIR
EOF
