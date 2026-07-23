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

# Optional .xcresult capture. Set RESULT_BUNDLE=<path> on the `make`
# command line and the `build`, `build-ui-tests`, `test`, and `test-ui` targets
# append `-resultBundlePath` so CI can upload the bundle on failure. xcodebuild requires
# the path to not already exist, so each target removes a stale bundle first.
# Unset (a normal local `make`), RESULT_BUNDLE_FLAG expands to nothing and the
# invocation is unchanged.
RESULT_BUNDLE_FLAG := $(if $(RESULT_BUNDLE),-resultBundlePath "$(RESULT_BUNDLE)")

# The entitlements file the Vitrine target signs with, consumed by project.yml as
# ${VITRINE_ENTITLEMENTS_FILE} (XcodeGen resolves it to a literal at generate time,
# so there is no xcodebuild build-time variable that the CI runner stalls on). The
# default is the minimal App Store / minimal set; scripts/build-dmg.sh exports the
# direct-download superset (network + Sparkle XPC) before generating.
export VITRINE_ENTITLEMENTS_FILE ?= Vitrine/Resources/Vitrine.entitlements

# The direct-download license-signing private key (base64 of the raw Ed25519 32 bytes),
# consumed by project.yml as ${VITRINE_LICENSE_SIGNING_KEY} → the Info.plist's
# VitrineLicenseSigningKey (embedded-key activation model). Empty by default, so a normal/CI build
# cannot mint a license token and stays free; the release machine exports the real key
# before `make` / scripts/build-dmg.sh. Never store the real value in the repo — see
# docs/ACTIVATION.md.
export VITRINE_LICENSE_SIGNING_KEY ?=

.DEFAULT_GOAL := all
.PHONY: all bootstrap project open build cli test build-ui-tests test-ui perf record-goldens gallery site-test format lint hygiene changelog-check icon clean

## all: generate the project and open it in Xcode (default)
all: open

## bootstrap: verify required tooling is installed
bootstrap:
	@./scripts/verify-xcodegen-version.sh "$(XCODEGEN)"

## project: generate Vitrine.xcodeproj from project.yml
project: bootstrap
	./scripts/fetch-sparkle.sh
	$(XCODEGEN) generate

## open: open the generated project in Xcode
open: project
	open $(PROJECT)

## build: headless Debug compile-check via xcodebuild (no signing)
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle.
build: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO $(RESULT_BUNDLE_FLAG) build

## cli: build the command-line renderer. The built `vitrine-cli` binary lands
## in DerivedData next to its bundled Fonts/ and the Highlightr resource bundle; the
## xcodebuild log's final line prints CODESIGNING_FOLDER_PATH, or use:
##   xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -showBuildSettings | \
##     awk '/ BUILT_PRODUCTS_DIR /{print $$3"/vitrine-cli"}'
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
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle, which CI
## uploads on failure for offline triage.
test: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) test

## build-ui-tests: compile UI tests without requiring local automation permission
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle.
build-ui-tests: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) build-for-testing

## test-ui: run the UI smoke tests (XCTest/XCUIAutomation)
## The first local run prompts for the macOS automation permission (grant it
## once); the hosted CI images are provisioned for headless automation, so the
## `UI tests` job in ci.yml runs this on every PR/push — see docs/RELEASING.md.
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle.
## Set TEST_UI_SKIP="<test> <test>" to skip named tests when a display cannot
## host one (the display-geometry-sensitive tests skip themselves below the
## editor's minimum supported display; CI runs the full suite unskipped).
TEST_UI_SKIP_FLAGS = $(foreach t,$(TEST_UI_SKIP),-skip-testing:VitrineUITests/VitrineUITests/$(t))
test-ui: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) $(TEST_UI_SKIP_FLAGS) test

## perf: run only the render-latency performance budget
## Documented budget: default render target 300 ms after warm-up (PERF WARN past
## it); the suite fails only past the hard ceiling. Grep the log for `PERF`/`PERF
## WARN` lines, which carry median/p95 for each representative fixture.
## Serialized like `test` (see that target's CoreText rationale): the perf suite
## is CoreText-heavy, and a serial run also keeps latency numbers comparable.
perf: project
	env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' \
		-only-testing:VitrineTests/PerformanceTests test

## record-goldens: (re)generate the golden-image fixtures + manifest
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

## gallery: (re)generate the launch-gallery design-QA samples + manifest
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

## site-test: type-check, build, and validate the static Astro website
site-test:
	cd site && npm test

## format: format Swift sources in place (Apple swift-format)
format:
	$(SWIFTFORMAT) format --in-place --recursive Vitrine VitrineCLI Tests UITests

## lint: lint Swift sources and tracked repository metadata (fails on issues)
lint: hygiene
	$(SWIFTFORMAT) lint --strict --recursive Vitrine VitrineCLI Tests UITests

## hygiene: reject private planning identifiers and tracked planning artifacts
hygiene:
	./scripts/check-repository-hygiene.sh

## changelog-check: validate release version and changelog link traceability
changelog-check:
	@cl=$$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); \
	mv=$$(grep -m1 -oE 'MARKETING_VERSION: *"?[0-9][0-9A-Za-z.-]*' project.yml | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); \
	grep -q '^## \[Unreleased\]' CHANGELOG.md || { echo "✗ CHANGELOG.md is missing an [Unreleased] section"; exit 1; }; \
	[ -n "$$cl" ] || { echo "✗ no released '## [x.y.z]' heading in CHANGELOG.md"; exit 1; }; \
	[ "$$cl" = "$$mv" ] || { echo "✗ CHANGELOG top ($$cl) != MARKETING_VERSION ($$mv)"; exit 1; }; \
	grep -q "^\[Unreleased\]: https://github.com/johnny4young/vitrine/compare/v$$mv\.\.\.HEAD$$" CHANGELOG.md || \
		{ echo "✗ [Unreleased] compare link must start at v$$mv"; exit 1; }; \
	for version in $$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); do \
		grep -q "^\[$$version\]: https://" CHANGELOG.md || \
			{ echo "✗ CHANGELOG release $$version has no link definition"; exit 1; }; \
	done; \
	echo "✓ CHANGELOG $$cl matches MARKETING_VERSION $$mv and all release links are defined"

## icon: regenerate the app icon set (scripts/make-appicon.swift)
icon:
	swift scripts/make-appicon.swift

## clean: remove the generated project and build artifacts
clean:
	rm -rf $(PROJECT) build DerivedData
