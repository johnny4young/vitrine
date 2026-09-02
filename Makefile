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
# command line and the `build`, `build-release`, `build-ui-tests`, `test`,
# `test-coverage`, and `test-ui` targets append `-resultBundlePath` so CI can upload
# the bundle on failure. xcodebuild requires the path to not already exist, so each target
# removes a stale bundle first.
# Unset (a normal local `make`), RESULT_BUNDLE_FLAG expands to nothing and the
# invocation is unchanged.
RESULT_BUNDLE_FLAG := $(if $(RESULT_BUNDLE),-resultBundlePath "$(RESULT_BUNDLE)")

# Canonical strict visual-tour outputs. The XCTest runner always retains images in
# the result bundle; scripts/validate-screenshot-tour.py exports friendly PNG names
# from that bundle after proving the required set is complete.
VISUAL_OUTPUT ?= build/screenshot-tour
VISUAL_RESULT_BUNDLE ?= build/screenshot-tour.xcresult

# Coverage remains separate from the fast `make test` lane. Unlike optional
# diagnostic result bundles, this bundle is mandatory because the guard parses its
# xccov report and raw line archive. CI passes the explicit supported-platform key;
# local runs infer Sequoia/Tahoe from the host major version.
COVERAGE_RESULT_BUNDLE ?= $(or $(RESULT_BUNDLE),build/test-coverage.xcresult)
COVERAGE_PLATFORM ?= $(shell major=$$(sw_vers -productVersion | cut -d. -f1); \
	if [ "$$major" = 15 ]; then echo sequoia; \
	elif [ "$$major" = 26 ]; then echo tahoe; else echo unsupported; fi)
COVERAGE_BASELINE ?= scripts/coverage-baselines/$(COVERAGE_PLATFORM).json
COVERAGE_BASE_REF_FLAG := $(if $(COVERAGE_BASE_REF),--base-ref "$(COVERAGE_BASE_REF)",)

# Dynamic-memory evidence is intentionally local and review-driven. It reuses the normal
# Debug build and resolved exact package checkouts, then launches under `leaks`; optional
# MEMORY_BASELINE points at an earlier report.json for same-environment/same-journey
# deltas. MEMORY_JOURNEY selects one of the four bounded journeys below.
MEMORY_OUTPUT ?= build/memory-smoke
MEMORY_JOURNEY ?= editor-snapshot
MEMORY_BASELINE_FLAG := $(if $(MEMORY_BASELINE),--baseline "$(MEMORY_BASELINE)",)
MEMORY_ITERATIONS_FLAG := $(if $(MEMORY_ITERATIONS),--iterations "$(MEMORY_ITERATIONS)",)

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
.PHONY: all bootstrap project open build build-release cli test test-coverage coverage-check test-asan test-tsan build-ui-tests test-ui test-visual ui-test-preflight-check screenshot-tour-check perf memory-smoke memory-smoke-all memory-soak-matrix memory-smoke-check build-boundaries build-boundaries-check informational-update-check release-promotion-check qa-handoff-check record-goldens gallery site-test format lint hygiene changelog-check icon clean

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

## build-release: compile the optimized universal app without signing
## This gate catches optimizer-only failures that Debug cannot expose and explicitly
## proves both supported Mac architectures compile before packaging starts.
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle.
build-release: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO \
		ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' $(RESULT_BUNDLE_FLAG) build

## cli: build the command-line renderer. The built `vitrine-cli` binary lands
## in DerivedData next to its bundled Fonts/ and the Highlightr resource bundle; the
## xcodebuild log's final line prints CODESIGNING_FOLDER_PATH, or use:
##   xcodebuild -project $(PROJECT) -scheme $(CLI_SCHEME) -showBuildSettings | \
##     awk '/ BUILT_PRODUCTS_DIR /{print $$3"/vitrine-cli"}'
cli: project
	$(XCODEBUILD) -project $(PROJECT) -scheme $(CLI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

## test: run the unit test suite without coverage (fast local feedback)
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
## Xcode 26 can occasionally hang while finalizing coverage after every test has
## passed. Keep the default developer loop deterministic by disabling coverage
## explicitly; `test-coverage` is the CI parity lane that retains it.
## Set RESULT_BUNDLE=<path> to also write an .xcresult bundle.
test: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -enableCodeCoverage NO $(RESULT_BUNDLE_FLAG) test

## test-coverage: run the complete suite and enforce fail-closed coverage policy
## This intentionally uses the same serial scheduling as `test`, but overrides
## the scheme explicitly so a future project setting cannot silently disable CI
## coverage. The result bundle is mandatory: the guard fails if xccov cannot read
## it, rejects a production-target drop over one percentage point, and requires
## 80% coverage for changed executable lines in critical non-visual logic.
## The instrumented test host runs without the product sandbox only in this lane.
## Otherwise privacy-hardened macOS hosts can prevent xcodebuild from retrieving
## the raw profile from the app container, leaving an unreadable coverage archive.
## These command-line overrides do not change the generated product configuration.
test-coverage: project
	@test -f "$(COVERAGE_BASELINE)" || { \
		echo "Unsupported coverage platform '$(COVERAGE_PLATFORM)' or missing baseline: $(COVERAGE_BASELINE)" >&2; \
		exit 1; \
	}
	@rm -rf "$(COVERAGE_RESULT_BUNDLE)"
	env SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -enableCodeCoverage YES \
		CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO \
		-resultBundlePath "$(COVERAGE_RESULT_BUNDLE)" test
	python3 scripts/check-coverage.py \
		--result-bundle "$(COVERAGE_RESULT_BUNDLE)" \
		--baseline "$(COVERAGE_BASELINE)" \
		$(COVERAGE_BASE_REF_FLAG)

## coverage-check: validate parser, scope, and fail-closed behavior without Xcode
coverage-check:
	python3 scripts/check-coverage.py --self-test

# Sanitizers intentionally exercise focused model, parser, file-safety, and
# asynchronous-lifecycle suites instead of the full AppKit/WebKit UI host. The
# weekly/manual hosted workflow retains each result bundle. These lanes are
# non-required early warnings until their runner stability has been established.
ASAN_TEST_SELECTION := \
	-only-testing:VitrineTests/ANSIParserTests \
	-only-testing:VitrineTests/TerminalGridTests \
	-only-testing:VitrineTests/RenderBudgetTests \
	-only-testing:VitrineTests/BoundedFileReaderTests \
	-only-testing:VitrineTests/AsciinemaCastTests \
	-only-testing:VitrineTests/FileInputLoaderDecodeTests \
	-only-testing:VitrineTests/FileInputLoaderDecodeTextTests \
	-only-testing:VitrineTests/ImageSecretRedactorTests \
	-only-testing:VitrineTests/PrivateNetworkBlockRulesTests

TSAN_TEST_SELECTION := \
	-only-testing:VitrineTests/DebouncerTests \
	-only-testing:VitrineTests/ItemProviderLoadWaiterTests \
	-only-testing:VitrineTests/WebLoadWaiterTests \
	-only-testing:VitrineTests/MemoryWebSnapshotCycleJourneyTests

## test-asan: run focused allocation/input/parser logic under Address Sanitizer
test-asan: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -enableCodeCoverage NO \
		-enableAddressSanitizer YES $(RESULT_BUNDLE_FLAG) \
		$(ASAN_TEST_SELECTION) test

## test-tsan: run focused cancellation/waiter lifecycle logic under Thread Sanitizer
test-tsan: project
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS' -enableCodeCoverage NO \
		-enableThreadSanitizer YES $(RESULT_BUNDLE_FLAG) \
		$(TSAN_TEST_SELECTION) test

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
	python3 scripts/check-ui-test-environment.py
	@$(if $(RESULT_BUNDLE),rm -rf "$(RESULT_BUNDLE)")
	$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
		-destination 'platform=macOS' $(RESULT_BUNDLE_FLAG) $(TEST_UI_SKIP_FLAGS) test

## ui-test-preflight-check: validate foreign-runner detection without inspecting live processes
ui-test-preflight-check:
	python3 scripts/check-ui-test-environment.py --self-test

## screenshot-tour-check: validate the required screenshot manifest and source contract
screenshot-tour-check:
	python3 scripts/validate-screenshot-tour.py \
		--manifest UITests/ScreenshotTourManifest.json \
		--source UITests/ScreenshotTourUITests.swift

## test-visual: run the strict visual tour and export its complete xcresult evidence
## Missing states, foreground-app contamination, duplicate images, invalid PNGs,
## and source/manifest drift all fail this gate. Friendly PNGs land in
## VISUAL_OUTPUT; override VISUAL_RESULT_BUNDLE to retain the raw bundle elsewhere.
test-visual: project screenshot-tour-check
	python3 scripts/check-ui-test-environment.py
	@rm -rf "$(VISUAL_OUTPUT)" "$(VISUAL_RESULT_BUNDLE)"
	@status=0; \
		env TEST_RUNNER_VITRINE_SCREENSHOT_DIR="$(abspath $(VISUAL_OUTPUT))" \
		$(XCODEBUILD) -project $(PROJECT) -scheme $(UI_SCHEME) -configuration Debug \
			-destination 'platform=macOS' \
			-resultBundlePath "$(VISUAL_RESULT_BUNDLE)" \
			-only-testing:VitrineUITests/ScreenshotTourUITests test || status=$$?; \
		python3 scripts/validate-screenshot-tour.py \
			--manifest UITests/ScreenshotTourManifest.json \
			--source UITests/ScreenshotTourUITests.swift \
			--result-bundle "$(VISUAL_RESULT_BUNDLE)" \
			--output "$(VISUAL_OUTPUT)" || status=$$?; \
		exit $$status

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

## memory-smoke: capture an editor memgraph and parsed at-exit leak evidence
## This is an evidence lane, not a zero-leak gate: Apple/WebKit roots and reachable
## growth require human classification. Compare a prior same-environment report with
## MEMORY_BASELINE=build/memory-smoke/<run>/report.json. Use
## MEMORY_JOURNEY=image-import-cycle for repeated isolated image import/decode evidence.
memory-smoke: build memory-smoke-check
	env DEVELOPER_DIR="$(XCODE_DEVELOPER)" python3 scripts/run-memory-smoke.py \
		--project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Debug \
		--output "$(MEMORY_OUTPUT)" --journey "$(MEMORY_JOURNEY)" \
		$(MEMORY_ITERATIONS_FLAG) $(MEMORY_BASELINE_FLAG)

## memory-smoke-all: capture all five bounded journeys sequentially against one clean build
## Baselines are intentionally per-journey; use memory-smoke when comparing one report.
memory-smoke-all: build memory-smoke-check
	@set -e; for journey in editor-snapshot image-import-cycle window-churn web-snapshot-cycle large-document-cycle; do \
		echo "==> memory smoke: $$journey"; \
		env DEVELOPER_DIR="$(XCODE_DEVELOPER)" python3 scripts/run-memory-smoke.py \
			--project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Debug \
			--output "$(MEMORY_OUTPUT)" --journey "$$journey"; \
	done

## memory-soak-matrix: record longitudinal 20/50/100 lifecycle profiles
## Runs four teardown-heavy journeys sequentially; generated memgraphs and JSON remain ignored.
memory-soak-matrix: build memory-smoke-check
	@set -e; for journey in image-import-cycle window-churn web-snapshot-cycle large-document-cycle; do \
		for iterations in 20 50 100; do \
			echo "==> memory soak: $$journey ($$iterations iterations)"; \
			env DEVELOPER_DIR="$(XCODE_DEVELOPER)" python3 scripts/run-memory-smoke.py \
				--project "$(PROJECT)" --scheme "$(SCHEME)" --configuration Debug \
				--output "$(MEMORY_OUTPUT)" --journey "$$journey" \
				--iterations "$$iterations" --launch-timeout 900 --analysis-timeout 300; \
		done; \
	done

## memory-smoke-check: validate the parser and baseline comparison without launching UI
memory-smoke-check:
	python3 scripts/run-memory-smoke.py --self-test

## build-boundaries: measure clean/no-op/incremental builds and focused test startup
## in disposable DerivedData. The JSON report and complete logs stay under ignored
## build/ paths. The default is seven samples; override it with
## BUILD_BOUNDARY_RUNS=<n>. Set
## BUILD_BOUNDARY_BASELINE=<report.json> to compare medians with an earlier run.
build-boundaries: project
	env DEVELOPER_DIR="$(XCODE_DEVELOPER)" python3 scripts/measure-build-boundaries.py \
		--runs "$(or $(BUILD_BOUNDARY_RUNS),7)" $(if $(BUILD_BOUNDARY_BASELINE),--baseline "$(BUILD_BOUNDARY_BASELINE)",)

## build-boundaries-check: validate the metric/statistics helpers without invoking Xcode
build-boundaries-check:
	python3 scripts/measure-build-boundaries.py --self-test

## informational-update-check: validate the appcast rewrite that reaches hosts whose updater cannot install
informational-update-check:
	python3 scripts/mark-informational-update.py --self-test

## release-promotion-check: validate fail-closed candidate provenance and approval rules
release-promotion-check:
	python3 scripts/verify-release-promotion.py --self-test

## qa-handoff-check: validate clean-Mac WebKit fixtures and structured log templates
qa-handoff-check:
	./scripts/build-qa-handoff.sh --self-test

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
	$(SWIFTFORMAT) format --in-place --recursive Vitrine VitrineDomain VitrineRendering VitrineCLI VitrineMenuBarHelper DomainTests RenderingTests Tests UITests

## lint: lint Swift sources and tracked repository metadata (fails on issues)
lint: hygiene build-boundaries-check informational-update-check release-promotion-check qa-handoff-check memory-smoke-check ui-test-preflight-check screenshot-tour-check
	$(SWIFTFORMAT) lint --strict --recursive Vitrine VitrineDomain VitrineRendering VitrineCLI VitrineMenuBarHelper DomainTests RenderingTests Tests UITests

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
