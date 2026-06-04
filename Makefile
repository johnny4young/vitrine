# Vitrine — developer tasks
#
# `project.yml` is the source of truth; `Vitrine.xcodeproj` is generated and
# git-ignored. See CONTRIBUTING.md.

PROJECT  := Vitrine.xcodeproj
SCHEME   := Vitrine
XCODEGEN := xcodegen

# Use full Xcode for xcodebuild even when `xcode-select` points at the Command
# Line Tools (a common setup). Falls back to whatever xcode-select reports.
XCODE_DEVELOPER := $(or $(DEVELOPER_DIR),$(shell [ -d "/Applications/Xcode.app/Contents/Developer" ] \
	&& echo "/Applications/Xcode.app/Contents/Developer" || xcode-select -p))
XCODEBUILD := env DEVELOPER_DIR="$(XCODE_DEVELOPER)" xcodebuild
SWIFTFORMAT := env DEVELOPER_DIR="$(XCODE_DEVELOPER)" xcrun swift-format

.DEFAULT_GOAL := all
.PHONY: all bootstrap project open build format lint clean

## all: generate the project and open it in Xcode (default)
all: open

## bootstrap: verify required tooling is installed
bootstrap:
	@command -v $(XCODEGEN) >/dev/null 2>&1 || { \
		echo "✗ xcodegen not found — install with: brew install xcodegen"; exit 1; }
	@echo "✓ xcodegen $$($(XCODEGEN) --version)"

## project: generate Vitrine.xcodeproj from project.yml
project: bootstrap
	$(XCODEGEN) generate

## open: open the generated project in Xcode
open: project
	open $(PROJECT)

## build: headless Debug compile-check via xcodebuild (no signing)
build: project
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

## format: format Swift sources in place (Apple swift-format)
format:
	$(SWIFTFORMAT) format --in-place --recursive Vitrine

## lint: lint Swift sources without modifying them (fails on issues)
lint:
	$(SWIFTFORMAT) lint --strict --recursive Vitrine

## clean: remove the generated project and build artifacts
clean:
	rm -rf $(PROJECT) build DerivedData
