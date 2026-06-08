# Vitrine — developer tasks
#
# `project.yml` is the source of truth; `Vitrine.xcodeproj` is generated and
# git-ignored. See CONTRIBUTING.md.

PROJECT  := Vitrine.xcodeproj
SCHEME   := Vitrine
UI_SCHEME := VitrineUITests
CLI_SCHEME := VitrineCLI
XCODEGEN := xcodegen

# Use full Xcode for xcodebuild even when `xcode-select` points at the Command
# Line Tools (a common setup). Falls back to whatever xcode-select reports.
XCODE_DEVELOPER := $(or $(DEVELOPER_DIR),$(shell [ -d "/Applications/Xcode.app/Contents/Developer" ] \
	&& echo "/Applications/Xcode.app/Contents/Developer" || xcode-select -p))
XCODEBUILD := env DEVELOPER_DIR="$(XCODE_DEVELOPER)" xcodebuild
SWIFTFORMAT := env DEVELOPER_DIR="$(XCODE_DEVELOPER)" xcrun swift-format

# Optional .xcresult capture (CS-060). Set RESULT_BUNDLE=<path> on the `make`
# command line and the `build`, `build-ui-tests`, and `test` targets append
# `-resultBundlePath` so CI can upload the bundle on failure. xcodebuild requires
# the path to not already exist, so each target removes a stale bundle first.
# Unset (a normal local `make`), RESULT_BUNDLE_FLAG expands to nothing and the
# invocation is unchanged.
RESULT_BUNDLE_FLAG := $(if $(RESULT_BUNDLE),-resultBundlePath "$(RESULT_BUNDLE)")

# Ad-hoc code signing for the headless compile-check (`build`, `cli`). Sparkle
# (CS-064) embeds a dynamic framework with CodeSignOnCopy, which hangs under a
# no-signing compile-check on a headless CI runner with no identity to satisfy
# the copy. Ad-hoc ("-") gives a deterministic identity so the embed signs
# without hanging; the distributable build (scripts/build-dmg.sh) re-signs with
# the real Developer ID. `test`/`build-ui-tests` already use default ad-hoc.
ADHOC_SIGN := CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual

.DEFAULT_GOAL := all
.PHONY: all bootstrap project open build cli test build-ui-tests test-ui perf record-goldens gallery format lint icon clean

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

## build: headless Debug compile-check via xcodebuild (ad-hoc signing)
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle (CS-060).
build: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(ADHOC_SIGN) $(RESULT_BUNDLE_FLAG) build

## cli: build the command-line renderer `vitrine` (CS-033). The built binary lands
## in DerivedData next to its bundled Fonts/ and the Highlightr resource bundle; the
## xcodebuild log's final line prints CODESIGNING_FOLDER_PATH, or use:
##   xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -showBuildSettings | \
##     awk '/ BUILT_PRODUCTS_DIR /{print $$3"/vitrine"}'
cli: project
	$(XCODEBUILD) -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

## test: run the unit test suite (Swift Testing)
## Swift Testing parallelizes suites across threads by default. Several suites
## measure and rasterize text through CoreText (NSString.size(withAttributes:),
## ImageRenderer), and CoreText's typesetter is not safe to drive concurrently
## from multiple threads: under load it intermittently throws
## NSInvalidArgumentException ("attempt to insert nil object") from an unrelated
## text-measurement call, crashing the run. Production never hits this — every
## such call happens on the main actor inside SwiftUI `body` — so the fix belongs
## in how the harness schedules tests, not in product code. Pinning the
## parallelization width to 1 serializes the run and removes the race; the suite
## is dominated by serial main-actor rendering, so wall-clock cost is negligible.
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle (CS-060), which CI
## uploads on failure for offline triage.
test: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) test

## build-ui-tests: compile UI tests without requiring local automation permission
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle (CS-060).
build-ui-tests: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) build-for-testing

## test-ui: run the UI smoke tests (XCTest/XCUIAutomation)
test-ui: project
	$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' test

## perf: run only the render-latency performance budget (CS-026)
## Documented budget: default render target 300 ms after warm-up (PERF WARN past
## it); the suite fails only past the hard ceiling. Grep the log for `PERF`/`PERF
## WARN` lines, which carry median/p95 for each representative fixture.
perf: project
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' \
		-only-testing:VitrineTests/PerformanceTests test

## record-goldens: (re)generate the golden-image fixtures + manifest (CS-025)
## The single command that refreshes the visual baseline. It runs only the
## opt-in recorder test (gated by VITRINE_RECORD_GOLDENS) through the same render
## path the suite compares, then copies the staged PNGs and the platform manifest
## into Tests/Fixtures/Golden/. The recorder stages files in the sandboxed test
## host's container temp, so the copy step is handled by scripts/record-goldens.sh.
## Run this on the pinned runner image when a deliberate visual change lands, then
## review and commit the diff.
record-goldens: project
	env DEVELOPER_DIR="$(XCODE_DEVELOPER)" PROJECT="$(PROJECT)" SCHEME="$(SCHEME)" \
		bash scripts/record-goldens.sh

## gallery: (re)generate the launch-gallery design-QA samples + manifest (CS-039)
## The single command that refreshes the README/release-notes screenshot evidence.
## It runs only the opt-in generator test (gated by VITRINE_GENERATE_GALLERY)
## through the real export pipeline, then copies the staged PNGs and the manifest
## into Tests/Fixtures/Samples/. Like record-goldens, the generator stages files in
## the sandboxed test host's container temp, so the copy step is handled by
## scripts/generate-launch-gallery.swift. Run this when a deliberate visual change
## lands, then review and commit the diff.
gallery: project
	env DEVELOPER_DIR="$(XCODE_DEVELOPER)" PROJECT="$(PROJECT)" SCHEME="$(SCHEME)" \
		swift scripts/generate-launch-gallery.swift

## format: format Swift sources in place (Apple swift-format)
format:
	$(SWIFTFORMAT) format --in-place --recursive Vitrine VitrineCLI Tests UITests

## lint: lint Swift sources without modifying them (fails on issues)
lint:
	$(SWIFTFORMAT) lint --strict --recursive Vitrine VitrineCLI Tests UITests

## icon: regenerate the app icon set (scripts/make-appicon.swift)
icon:
	swift scripts/make-appicon.swift

## clean: remove the generated project and build artifacts
clean:
	rm -rf $(PROJECT) build DerivedData
