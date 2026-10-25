# Comparison-board encoding contract

Comparison boards compose their finished capture pixels once, then use
`ExportManager.encodedPayloadChecked` to choose the PDF or raster encoder and return
the data, content type and extension. The shared checked facade already owns that
policy for snapshot, social-card, CLI and App Intent exports.

The previous board exporter repeated the PDF/raster branch and encoder failure
guards after composition. Delegating that block removes a second policy owner; it
does not remove an API or change the rendered content. The composition error mapping
stays in the board exporter. This is a maintenance refactor, not a demonstrated
speedup or a fix for an observed output defect.

## Behavior to preserve

- A draft renders each selected capture only when it is created. Exporting formats
  reuses those pixels and the scale captured by the draft.
- PNG, HEIC and AVIF retain their actual container type and matching extension.
  Availability comes from the running ImageIO writer set, not a hardcoded OS check.
- PDF wraps the finished board pixels in one page. Its point dimensions equal the
  pixel dimensions divided by the captured scale; it does not recreate editable
  source vectors.
- A missing writer reports `RenderBudgetError.encodingFailed`. An invalid board
  retains its existing `.allocationFailed` mapping, and the optional convenience
  entry point returns `nil`.
- Source rendering, color normalization, layout, captions, publication, cancellation,
  SavePanel and sharing behavior are outside the implementation change.

## Reproduce with repository tests

Base: `62d7d570a4799e587d4f6a9c6be99cfa2ff3914e`, version 1.3.0/build 39.
Use separate fresh baseline and candidate checkouts. Copy the candidate's final
`Tests/ComparisonBoardExportTests.swift` into the baseline checkout so both sides run
the same assertions. No production file is copied back into the baseline.

The fixture is embedded in that test file: two synthetic captures and an injected
Core Graphics bitmap. It needs no user content, clipboard, license, remote page,
image-store entry or private report. The existing test covers 2x PNG/PDF dimensions;
the added parameterized cases cover every format's 1x container/dimensions and the
checked/optional invalid-draft contracts. Both sides should pass: a refactor is not
expected to produce a red baseline.

These tests belong to the app-hosted `VitrineTests` target. Use a disposable macOS CI
runner or an agreed isolated app-host session; a separate checkout alone does not
isolate a personal desktop or preference domain. The local laboratory instead runs
the same core sources in an isolated command-line probe; that is not native UI
qualification.

Run in each checkout with full Xcode and the repository's exact package versions:

```sh
make project
encoding_root=$(mktemp -d /tmp/vitrine-encoding-XXXXXX)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Vitrine.xcodeproj -scheme Vitrine -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$encoding_root/DerivedData" \
  -clonedSourcePackagesDirPath "$encoding_root/Packages" \
  -packageCachePath "$encoding_root/PackageCache" -jobs 1 \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:VitrineTests/ComparisonBoardExportTests \
  -resultBundlePath "$encoding_root/encoding.xcresult" test
```

Keep the fresh result directory and xcresult as evidence. `build-for-testing` compiles the
actual test file without running the app host when only compile validation is safe.
Normal repository gates are `make format`, `make lint` and `make build`. Dependencies
remain Highlightr 2.3.0, KeyboardShortcuts 2.4.0 and the checksum-pinned Sparkle from
`scripts/sparkle-version.env`; no lock, codec or golden baseline should be updated
for this change.

## Local diagnostic evidence and limits

The private before/after probe uses unchanged source copies from the exact base and
candidate. Its fixed board journey checks approved text, explicit order, retained
scale, PNG/PDF geometry, neutral-canary output controls, typed failures, preview
retry and local non-replacing publication/cancellation. A separate four-format
matrix decodes real containers and records runtime writer availability. Before/after
comparisons use PNG bytes and decoded pixels/PDF page rasters, not PDF timestamps.

Validation results are recorded in the pull request. Local macOS 27.0.1 (26A434),
Xcode 27.1 (27A9275), Swift 6.4 results are diagnostic; supported macOS 15/26 CI remains
the platform gate. No UI, performance budget, leak-absence or full-format visual
qualification follows from these functional checks. No goldens are regenerated.
