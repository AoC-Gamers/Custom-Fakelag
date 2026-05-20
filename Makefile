SHELL := /usr/bin/env bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DEPS_DIR ?= $(ROOT_DIR)/.deps
SMX_BUILD_DIR ?= $(ROOT_DIR)/.build/plugins
LINUX_BUILD_DIR ?= $(ROOT_DIR)/.build/linux-l4d2
WINDOWS_BUILD_DIR ?= $(ROOT_DIR)/.build/windows-l4d2
SMX_PACKAGE_DIR ?= $(ROOT_DIR)/.build/package-smx
EXTS_PACKAGE_LINUX_DIR ?= $(ROOT_DIR)/.build/package-exts-linux
EXTS_PACKAGE_WINDOWS_DIR ?= $(ROOT_DIR)/.build/package-exts-windows
LINUX_RELEASE_BASENAME ?= custom-fakelag-linux-local
WINDOWS_RELEASE_BASENAME ?= custom-fakelag-windows-local

ifeq ($(OS),Windows_NT)
PYTHON := python
else
PYTHON := $(shell command -v python3 >/dev/null 2>&1 && echo python3 || echo python)
endif

.PHONY: help \
	deps-smx deps-exts-linux deps-exts-windows \
	build-smx build-exts-linux build-exts-windows \
	package-smx package-exts-linux package-exts-windows \
	release-linux release-windows \
	test-exts-linux test-exts-windows \
	clean-linux clean-windows

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make help                  Show this help message' \
		'  make deps-smx              Fetch SourceMod package deps for plugin compilation' \
		'  make deps-exts-linux       Fetch Linux build dependencies for the extension' \
		'  make deps-exts-windows     Fetch Windows build dependencies for the extension' \
		'  make build-smx             Build SourcePawn plugins' \
		'  make build-exts-linux      Build Linux extension package' \
		'  make build-exts-windows    Build Windows extension package' \
		'  make package-smx           Stage plugin package tree from existing SMX build' \
		'  make package-exts-linux    Stage Linux extension package tree from existing build' \
		'  make package-exts-windows  Stage Windows extension package tree from existing build' \
		'  make release-linux         Merge SMX and Linux extension packages into a ZIP' \
		'  make release-windows       Merge SMX and Windows extension packages into a ZIP' \
		'  make test-exts-linux       Build and run standalone extension tests on Linux/WSL' \
		'  make test-exts-windows     Build and run standalone extension tests on Windows' \
		'  make clean-linux           Remove Linux build outputs' \
		'  make clean-windows         Remove Windows build outputs'

deps-smx:
	$(PYTHON) ./scripts/fetch-plugin-deps.py --root .

deps-exts-linux:
	bash ./scripts/fetch-linux-deps.sh

deps-exts-windows:
	pwsh -File ./scripts/fetch-windows-deps.ps1

build-smx:
	$(PYTHON) ./scripts/build-plugins.py --root . --output-root "$(SMX_BUILD_DIR)"

build-exts-linux:
	bash ./scripts/build-linux-l4d2.sh

build-exts-windows:
	pwsh -File ./scripts/build-windows-l4d2.ps1

package-smx:
	$(PYTHON) ./scripts/copy-tree.py --source "$(SMX_BUILD_DIR)" --output "$(SMX_PACKAGE_DIR)"

package-exts-linux:
	$(PYTHON) ./scripts/copy-tree.py --source "$(LINUX_BUILD_DIR)/package" --output "$(EXTS_PACKAGE_LINUX_DIR)"

package-exts-windows:
	$(PYTHON) ./scripts/copy-tree.py --source "$(WINDOWS_BUILD_DIR)/package" --output "$(EXTS_PACKAGE_WINDOWS_DIR)"

release-linux:
	$(PYTHON) ./scripts/stage-artifact.py "$(ROOT_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_LINUX_DIR)"
	$(PYTHON) ./scripts/package-release.py --root "$(ROOT_DIR)" --basename "$(LINUX_RELEASE_BASENAME)"

release-windows:
	$(PYTHON) ./scripts/stage-artifact.py "$(ROOT_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_WINDOWS_DIR)"
	$(PYTHON) ./scripts/package-release.py --root "$(ROOT_DIR)" --basename "$(WINDOWS_RELEASE_BASENAME)"

test-exts-linux:
	bash ./scripts/run-linux-tests.sh

test-exts-windows:
	pwsh -File ./scripts/run-windows-tests.ps1

clean-linux:
	rm -rf "$(LINUX_BUILD_DIR)" "$(SMX_BUILD_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_LINUX_DIR)" "$(ROOT_DIR)/dist"

clean-windows:
	rm -rf "$(WINDOWS_BUILD_DIR)" "$(SMX_BUILD_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_WINDOWS_DIR)" "$(ROOT_DIR)/dist"
