# Documentation export UI profiling

The documentation-package test deliberately covers eight states: English/Spanish,
light/dark appearance, and minimum/1280×800 windows. Each state launches an isolated
app, enters alternative text through accessibility, configures a package, visits the
real folder panel, exports, and verifies image.png, README.md, index.html and source.txt.
The separate cancellation test remains part of the ordinary UI suite.

## Diagnostic evidence

The test emits `DOCUMENTATION_UI_SEGMENT` lines using monotonic system uptime:

- launch: isolated app creation, launch and activation
- navigation: editor geometry and output-inspector navigation
- description: alternative-text entry and acceptance
- package-setup: menu, sheet, folder-name entry, output selections and screenshot
- panel: export click, Go to Folder typing, and localized panel readiness
- export: panel confirmation until the export sheet disappears
- validation: all four files and their text/alternative-text content
- termination: explicit app termination

Each segment includes automation overhead. In particular, `export` is not a pure
renderer benchmark. Assertions, timeouts and test selection are unchanged. These
markers add measurement overhead and do not themselves optimize the test.

Save the complete ordinary-UI job log for one OS and one attempt, then run:

```sh
python3 scripts/summarize-documentation-ui.py job.log > timing.json
python3 scripts/summarize-documentation-ui.py --self-test
```

The summary fails closed on missing states/phases, duplicates, unknown labels and
nonfinite/negative durations. Do not combine two OS jobs or reruns in one input.
Passing timing parsing is not proof that the entire UI job passed; retain the exact
source head, run/job URL, Xcode/image identity, xcresult and terminal job conclusion.
A failed/incomplete test must not become a successful performance observation.

## Controlled qualification before optimization claims

First collect instrumentation-only baseline evidence. Then change only the measured
bottleneck while keeping eight states, real panel interactions, typing acceptance,
all file checks, cancellation and screenshot coverage intact. Compare matched base
and candidate runs on the same OS, Xcode version and runner image. Record queue time
separately from executed job, step and test durations. Five matched pairs per OS are
the qualification target; fewer pairs are diagnostic and remain unqualified. Do not
claim a 20–30% improvement from historic runs across different source commits.

Keep Tahoe strict pixel-golden comparison separate from Sequoia render-only smoke.
Do not drop OS/locale states, relax timeout or performance/coverage floors, suppress
unexpected skips, reuse instrumented coverage products for performance, or share
build products across SDK/configuration/signing/sandbox boundaries.

The performance lane's compile/link overhead is a separate hypothesis. Inspect the
actual build graph and configuration differences before proposing reuse. Existing
lane-partition checks already prevent duplicated performance/golden coverage work;
that existing behavior is not a new optimization.

## Already-ready folder-panel checks

The folder-panel journey checks the current `exists`/`isHittable` state before
starting XCTest's polling waits. The same three assertions and five-second
fallback waits remain: the real open panel must exist, its scoped OK button must
exist, and that button must be hittable. Export still uses the native button after
Go to Folder keyboard navigation and path entry; no pasteboard shortcut, seeded
panel location, or programmatic export replaces that interaction.

This avoids invoking the polling wait when readiness is already established.
It is a candidate optimization, not a guaranteed duration reduction: extra
accessibility queries can have a cost, especially when readiness is delayed.
A focused control test verifies that already-ready state avoids the fallback,
delayed readiness returns its successful fallback result, and a missing control
retains the fallback failure. These are synthetic readiness controls, not a
simulated delayed or missing native panel.
Use the identical eight-phase markers and matched-run protocol above to determine
its effect. A single candidate CI run versus a historical baseline is diagnostic;
it cannot establish a reproducible improvement or quantify workflow savings.
