# Content-rule store testability

`WebSnapshotView` and `URLSnapshotEngine` accept an internal
`contentRuleListStoreSource`. Its default is `.applicationDefault`: existing callers
still obtain `WKContentRuleListStore.default()`, use the same process-wide compiled
caches, identifiers, rule JSON and failure mapping. No setting, entitlement, network
policy, cancellation behavior or persistent website-data mode changes.

An explicit `.directory(url)` uses `WKContentRuleListStore(url:)` and bypasses the
application's shared compiled-list caches. A custom-store failure never falls back
to the application store. Non-file, relative, remote-authority, query and fragment
locations are refused before either factory runs. The caller must still prove that
the directory is owned: this value does not resolve symlinks, create directories,
grant access, establish filesystem ownership or clean anything up.

The pure selector and its WebKit adapter are separate files. Selecting a source is
inert; the concrete store is created only when the engine requests its rules.

## Reproduce without WebKit

Requires macOS and full Xcode with Swift 6.2 or newer. The base for this change is
`62d7d570a4799e587d4f6a9c6be99cfa2ff3914e`, Vitrine 1.3.0/build 39. Use fresh independent
baseline and candidate checkouts. From the candidate checkout:

```sh
probe_parent=$(mktemp -d /tmp/vitrine-rule-store-XXXXXX)
python3 scripts/test-web-rule-store.py \
  --source-checkout /path/to/fresh-baseline --waiter-only \
  --output "$probe_parent/baseline"
python3 scripts/test-web-rule-store.py --output "$probe_parent/candidate"
```

The script refuses an existing output path, uses a clean child environment and
owned caches, selects one compiler worker and bounds its owned process group. It
runs a standalone Swift executable without Swift Testing, XCTest or a test host. It does not delete
earlier evidence, download packages or launch Vitrine.app.

It copies the actual pure selector and `WebLoadWaiter`, the exact
`WebSnapshotError` declaration and the real RenderBudget/Domain dependencies into a
temporary Swift package. Independent contract oracles call those real sources;
the canonical app-hosted test methods are not executed by this probe. The WebKit
adapter, engines, test frameworks and app graph are excluded. A separate guard asserts
that no WebKit or legacy WebKit framework image is loaded in the test process.
Source hashes, command/environment metadata and stdout/stderr are retained under
the output directory. Treat raw local logs as private until reviewed.

The selector suite uses inert string stores. It checks default/custom factory
selection, cache eligibility, exact URL forwarding, nil propagation without
fallback and five invalid URL forms. No actual rule-store directory or WebKit
object is created by those tests.

The retained baseline probe covers six waiter contracts plus before/after framework
guards. The candidate adds nine selector cases, including five invalid URL forms.
The separate canonical selector suite has five methods, one parameterized over those
five forms; its app-hosted execution is a distinct gate. The same waiter checks early outcomes, first-outcome ownership, concurrent
wait rejection, timeout, pending cancellation and cancellation before waiting.
Those exercise real state-machine behavior, not actual WebKit navigation cancellation.

Normal repository gates remain `make format`, `make lint` and `make build`.
`build-for-testing` can compile the actual app test file without executing its host;
compilation is not functional coverage. Canonical app-host execution belongs in an
isolated session or disposable CI runner. Do not run the broad controlled WebKit
suite on a personal desktop merely because these hostless checks pass.

## Future contained WebKit fixture

The new seam permits the actual engine to use an owned rule directory:

```swift
let source = WebContentRuleListStoreSource.directory(ownedRuleDirectory)
let htmlEngine = WebSnapshotView(contentRuleListStoreSource: source)
// Debug builds also expose the existing website-data-store injection.
let urlEngine = URLSnapshotEngine(
    contentRuleListStoreSource: source,
    websiteDataStore: isolatedWebsiteStore)
```

This example is not a complete containment boundary. Before creating any WebKit
object, prove the rule, profile, cache, preference and credential boundaries. Use a
fresh nonpersistent website store and configure its owned nonforwarding loopback
proxy before view creation, with failover disabled and no direct destination bypass.
Do not read, enumerate or clear default/persistent stores. No login windows, real
credentials, remote sites, new permissions, sandbox-disabling overrides or system
proxy/DNS changes are needed or justified by this seam.

Only after those prerequisites hold, use a small synthetic 320x240/1x fixture on an
owned port. Observe the held request before cancellation, require CancellationError
without an image, release the hold, retry, verify a bounded timeout and close only
owned resources. Preserve real rule compilation failures as fail-closed; do not
restore the removed HTML policy-widening flag or bypass the rule list.

The existing 13 controlled WebKit cases are separately gated by
`VITRINE_WEB_FIXTURE_PORT`. Their historical skips remain skips; inert construction
and waiter tests do not replace them. This change alone does not prove all WebKit
child-process/support-file paths are contained or establish native capture,
performance, leak-absence or complete UX qualification.
