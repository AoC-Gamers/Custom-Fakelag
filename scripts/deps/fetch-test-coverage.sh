#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_DIR="${COVERAGE_VENV_DIR:-$ROOT_DIR/.deps/test-coverage}"
"${PYTHON:-python3}" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --only-binary=:all: -r "$ROOT_DIR/tests/requirements-coverage.txt"
