SHELL := /usr/bin/env bash

ROOT_DIR := $(shell cd "$$(dirname "$(MAKEFILE_LIST)")" && pwd)
DEPS_DIR ?= $(ROOT_DIR)/.deps
SMX_DEPS_DIR ?= $(DEPS_DIR)/smx
EXTS_LINUX_DEPS_DIR ?= $(DEPS_DIR)/exts-linux
EXTS_WINDOWS_DEPS_DIR ?= $(DEPS_DIR)/exts-windows
SMX_BUILD_DIR ?= $(ROOT_DIR)/.build/plugins
LINUX_BUILD_DIR ?= $(ROOT_DIR)/.build/linux-l4d2
WINDOWS_BUILD_DIR ?= $(ROOT_DIR)/.build/windows-l4d2
SMX_PACKAGE_DIR ?= $(ROOT_DIR)/.build/package-smx
EXTS_PACKAGE_LINUX_DIR ?= $(ROOT_DIR)/.build/package-exts-linux
EXTS_PACKAGE_WINDOWS_DIR ?= $(ROOT_DIR)/.build/package-exts-windows
LINUX_RELEASE_BASENAME ?= custom-fakelag-local-linux
WINDOWS_RELEASE_BASENAME ?= custom-fakelag-local-windows

ifeq ($(OS),Windows_NT)
PYTHON ?= python
else
PYTHON ?= $(shell command -v python3 >/dev/null 2>&1 && echo python3 || echo python)
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
		'Available targets (build/deps/package phases run in order):' \
		'  sonar-build sonar-cppcheck sonar (explicit local analysis)' \
		'  sonar-tooling-test coverage-tooling-test test-coverage test-python-coverage' \
		'  deps-sonar deps-test-coverage (explicit tool preparation)' \
		'  test-python test-consumers test-diagnostic-linux test-diagnostic-windows' \
		'  test-sdk-windows test-collection-windows validate-artifact-linux validate-artifact-windows' \
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
	DEPS_DIR="$(SMX_DEPS_DIR)" $(PYTHON) "$(ROOT_DIR)/scripts/deps/fetch-plugin-deps.py" --root "$(ROOT_DIR)"

deps-exts-linux:
	DEPS_DIR="$(EXTS_LINUX_DEPS_DIR)" bash "$(ROOT_DIR)/scripts/deps/fetch-linux-deps.sh"

deps-exts-windows:
	DEPS_DIR="$(EXTS_WINDOWS_DEPS_DIR)" pwsh -File "$(ROOT_DIR)/scripts/deps/fetch-windows-deps.ps1"

build-smx:
	DEPS_DIR="$(SMX_DEPS_DIR)" $(PYTHON) "$(ROOT_DIR)/scripts/build/build-plugins.py" --root "$(ROOT_DIR)" --output-root "$(SMX_BUILD_DIR)"

build-exts-linux:
	BUILD_DIR="$(LINUX_BUILD_DIR)" DEPS_DIR="$(EXTS_LINUX_DEPS_DIR)" bash "$(ROOT_DIR)/scripts/build/build-linux-l4d2.sh"

build-exts-windows:
	BUILD_DIR="$(WINDOWS_BUILD_DIR)" DEPS_DIR="$(EXTS_WINDOWS_DEPS_DIR)" pwsh -File "$(ROOT_DIR)/scripts/build/build-windows-l4d2.ps1"

package-smx:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/copy-tree.py" --source "$(SMX_BUILD_DIR)" --output "$(SMX_PACKAGE_DIR)"

package-exts-linux:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/copy-tree.py" --source "$(LINUX_BUILD_DIR)/package" --output "$(EXTS_PACKAGE_LINUX_DIR)"

package-exts-windows:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/copy-tree.py" --source "$(WINDOWS_BUILD_DIR)/package" --output "$(EXTS_PACKAGE_WINDOWS_DIR)"

release-linux:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/stage-artifact.py" "$(ROOT_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_LINUX_DIR)" --platform linux
	$(PYTHON) "$(ROOT_DIR)/scripts/package/package-release.py" --root "$(ROOT_DIR)" --basename "$(LINUX_RELEASE_BASENAME)" --platform linux

release-windows:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/stage-artifact.py" "$(ROOT_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_WINDOWS_DIR)" --platform windows
	$(PYTHON) "$(ROOT_DIR)/scripts/package/package-release.py" --root "$(ROOT_DIR)" --basename "$(WINDOWS_RELEASE_BASENAME)" --platform windows

test-exts-linux:
	bash "$(ROOT_DIR)/scripts/ci/run-linux-tests.sh"

test-exts-windows:
	pwsh -File "$(ROOT_DIR)/scripts/ci/run-windows-tests.ps1"

clean-linux:
	$(PYTHON) "$(ROOT_DIR)/scripts/tools/clean.py" "$(LINUX_BUILD_DIR)" "$(SMX_BUILD_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_LINUX_DIR)" "$(ROOT_DIR)/dist/linux"

clean-windows:
	$(PYTHON) "$(ROOT_DIR)/scripts/tools/clean.py" "$(WINDOWS_BUILD_DIR)" "$(SMX_BUILD_DIR)" "$(SMX_PACKAGE_DIR)" "$(EXTS_PACKAGE_WINDOWS_DIR)" "$(ROOT_DIR)/dist/windows"

.PHONY: validate-artifact-linux validate-artifact-windows test-python
validate-artifact-linux:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/package-release.py" --root "$(ROOT_DIR)" --platform linux --basename "$(LINUX_RELEASE_BASENAME)" --validate-only
validate-artifact-windows:
	$(PYTHON) "$(ROOT_DIR)/scripts/package/package-release.py" --root "$(ROOT_DIR)" --platform windows --basename "$(WINDOWS_RELEASE_BASENAME)" --validate-only
test-python:
	cd "$(ROOT_DIR)" && $(PYTHON) -m unittest discover -s tests/python -p 'test_windows_shutdown_export.py'
	cd "$(ROOT_DIR)" && $(PYTHON) -m unittest discover -s tests/python -p 'test_windows_steam_debug_tools.py'
	cd "$(ROOT_DIR)" && $(PYTHON) -m unittest discover -s tests/python -p 'test_packaging.py'

.PHONY: test-consumers
test-consumers:
	cd "$(ROOT_DIR)" && bash "$(ROOT_DIR)/scripts/ci/test-consumers.sh"

.PHONY: test-diagnostic-linux
test-diagnostic-linux:
	cd "$(ROOT_DIR)" && bash "$(ROOT_DIR)/scripts/ci/test-diagnostic-linux.sh"

.PHONY: test-collection-windows
test-collection-windows:
	cd "$(ROOT_DIR)" && pwsh -NoProfile -File "$(ROOT_DIR)/scripts/ci/test-collection-windows.ps1"

.PHONY: test-diagnostic-windows
test-diagnostic-windows:
	cd "$(ROOT_DIR)" && pwsh -NoProfile -File "$(ROOT_DIR)/scripts/ci/test-diagnostic-windows.ps1"

.PHONY: test-sdk-windows
test-sdk-windows:
	pwsh -NoProfile -File "$(ROOT_DIR)/scripts/ci/test-windows-sdk-contract.ps1" -BuildOnly

.PHONY: release-identity-linux release-identity-windows
release-identity-linux:
	$(PYTHON) "$(ROOT_DIR)/scripts/ci/release-identity.py" --platform linux
release-identity-windows:
	$(PYTHON) "$(ROOT_DIR)/scripts/ci/release-identity.py" --platform windows

# Explicit local analysis only. Never add these targets to CI.
SONAR_BUILD_DIR ?= $(ROOT_DIR)/.build/sonar-native
TEST_OUTPUT ?= $(ROOT_DIR)/.build/coverage/run-$(shell date +%Y%m%dT%H%M%S)
COVERAGE_VENV_DIR ?= $(ROOT_DIR)/.deps/test-coverage
COVERAGE_PYTHON ?= $(COVERAGE_VENV_DIR)/bin/python
.PHONY: sonar-build sonar sonar-cppcheck sonar-tooling-test coverage-tooling-test test-coverage deps-test-coverage test-python-coverage
sonar-build:
	$(PYTHON) "$(ROOT_DIR)/scripts/tools/sonar-build.py" --output "$(SONAR_BUILD_DIR)"
sonar:
	$(PYTHON) "$(ROOT_DIR)/scripts/tools/make_sonar.py" analyze --compile-commands "$(SONAR_BUILD_DIR)/compile_commands.json"
sonar-cppcheck:
	$(PYTHON) "$(ROOT_DIR)/scripts/tools/make_sonar.py" cppcheck --compile-commands "$(SONAR_BUILD_DIR)/compile_commands.json"
sonar-tooling-test:
	$(PYTHON) "$(ROOT_DIR)/tests/python/sonar_tooling_test.py"
coverage-tooling-test:
	$(PYTHON) "$(ROOT_DIR)/tests/python/native_coverage_test.py"
test-coverage:
	$(PYTHON) "$(ROOT_DIR)/tests/runners/test-coverage.py" --output "$(TEST_OUTPUT)" --compile-commands "$(SONAR_BUILD_DIR)/compile_commands.json"
deps-test-coverage:
	COVERAGE_VENV_DIR="$(COVERAGE_VENV_DIR)" bash "$(ROOT_DIR)/scripts/deps/fetch-test-coverage.sh"
test-python-coverage:
	$(COVERAGE_PYTHON) "$(ROOT_DIR)/tests/runners/test-python-coverage.py" --output "$(TEST_OUTPUT)"
.PHONY: deps-sonar
# Ubuntu host helper; scanner/JDK are selected explicitly from the local environment.
deps-sonar:
	bash "$(ROOT_DIR)/scripts/deps/fetch-sonar-tools.sh"
