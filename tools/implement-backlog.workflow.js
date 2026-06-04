export const meta = {
  name: 'implement-backlog',
  description: 'Implement Vitrine backlog tickets serially with build/lint/test gates, Swift-6 concurrency + macOS-HIG review-and-fix loops, unit-test audit, Desktop review artifacts, and a final commit message',
  whenToUse: 'When implementing a batch of CS-XXX backlog tickets from docs/ROADMAP.md end to end.',
  phases: [
    { title: 'Plan' },
    { title: 'Implement' },
    { title: 'Artifacts' },
    { title: 'Wrap-up' },
  ],
}

// ---------------------------------------------------------------------------
// args (all optional):
//   { mode: 'plan' | 'run',            // 'plan' stops after the planning phase
//     tickets: ['CS-020', ...],        // explicit ticket IDs; overrides `select`
//     select: 'phase1' | 'worldclass' | 'all',
//     label: 'batch1' }                // Desktop artifact folder suffix
//
// ROBUSTNESS: only the (light) Plan agent uses a JSON schema. The heavy agents
// (implement / review / test-audit) return FREE TEXT ending in parseable marker
// lines (STATUS:/FILES:/FINDINGS:). A schema-constrained agent that does a lot of
// tool work sometimes ends its turn without emitting StructuredOutput and aborts
// the run; free-text agents always return their final text, so this can't happen.
// ---------------------------------------------------------------------------

const PHASE1 = Array.from({ length: 20 }, (_, i) => `CS-0${20 + i}`) // CS-020..CS-039
const WORLDCLASS = Array.from({ length: 8 }, (_, i) => `CS-0${47 + i}`) // CS-047..CS-054

const cfg = (typeof args === 'object' && args) ? args : {}
const mode = cfg.mode === 'plan' ? 'plan' : 'run'
const label = cfg.label || 'batch'
const select = cfg.select || 'all'
const tickets = Array.isArray(cfg.tickets) && cfg.tickets.length
  ? cfg.tickets
  : select === 'phase1' ? PHASE1
  : select === 'worldclass' ? WORLDCLASS
  : [...PHASE1, ...WORLDCLASS]

const ROADMAP = 'docs/ROADMAP.md'
const ARTIFACT_DIR = `~/Desktop/Vitrine-Review-${label}`

// --- marker parsers (heavy agents return free text ending in these lines) ---
function parseStatus(text) {
  const m = /STATUS:\s*(green|blocked)/i.exec(text || '')
  return m ? m[1].toLowerCase() : 'blocked'
}
function parseFiles(text) {
  const m = /FILES:\s*(.+)/i.exec(text || '')
  return m ? m[1].split(',').map(s => s.trim()).filter(Boolean) : []
}
function parseFindings(text) {
  const m = /FINDINGS:\s*(none|\d+)/i.exec(text || '')
  if (!m) return 0
  return m[1].toLowerCase() === 'none' ? 0 : (parseInt(m[1], 10) || 0)
}

// --- reviewer personas (custom agents may not be registered; embed criteria) ---
const CONCURRENCY_PERSONA = `You are a Swift 6 concurrency reviewer for Vitrine.
Ground truth: project.yml sets SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor and
SWIFT_APPROACHABLE_CONCURRENCY: YES, so code is @MainActor BY DEFAULT — do NOT flag missing
@MainActor annotations. Flag, in priority order: (1) real data races / non-Sendable values
crossing actor boundaries or captured by Task.detached; (2) legacy/deprecated APIs (HARD RULE:
none allowed — name the modern replacement, e.g. KeyboardShortcuts.events(_:for:) not .on);
(3) reintroduced nonisolated(unsafe)/@unchecked; (4) Task lifecycle leaks / missing cancellation
/ retain cycles; (5) moving SwiftUI/ImageRenderer view state off the main actor.`

const HIG_PERSONA = `You are a macOS Human Interface Guidelines reviewer for Vitrine (SwiftUI +
AppKit, agent app, Settings package panes with Form{}.formStyle(.grouped)). Check: layout &
spacing consistency; correct control choice/sizing; sentence-case labels; .help() tooltips;
accessibilityLabel/identifier coverage; keyboard operability; Light AND Dark mode via semantic
colors (no hardcoded hex for chrome); Dynamic Type; no white-on-white/invisible text; live
previews degrade gracefully; clean concise English copy.`

// --- the one place a schema is safe: the light, upfront Plan agent ---
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    order: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          isUI: { type: 'boolean' },
          rationale: { type: 'string' },
        },
        required: ['id', 'title', 'isUI'],
      },
    },
    sharedFileHotspots: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['order'],
}

const GATE = `Gate after every edit: run \`make lint && make build && make test\` and keep them ALL
green. project.yml edits auto-regenerate the project via a PostToolUse hook (or run \`xcodegen
generate\`). NEVER edit the generated Vitrine.xcodeproj. Respect Swift 6 MainActor default
isolation and use NO legacy/deprecated APIs. Committed prose/comments/UI strings must be clean
English. Do not run git commit. Take as many steps as you need; do not stop until the gate is
green or you are genuinely blocked.`

const MARK_IMPL = `When finished, end your FINAL message with EXACTLY these two lines (nothing after):
STATUS: green        (only if \`make lint && make build && make test\` ALL pass; else: STATUS: blocked — <short reason>)
FILES: <comma-separated list of files you created or modified>`

const MARK_REVIEW = `End your FINAL message with this line:
FINDINGS: none       (if no real issues; otherwise: FINDINGS: <integer count>)
followed by the findings list (severity / file / problem / concrete fix). Read-only — do not edit code.`

const MARK_AUDIT = `End your FINAL message with EXACTLY this line (nothing after):
STATUS: green        (tests adequate AND \`make test\` passes; else: STATUS: blocked — <short reason>)`

// =====================================================================
// Phase: Plan
// =====================================================================
phase('Plan')
const plan = await agent(
  `Plan a SAFE, dependency-ordered implementation sequence for these Vitrine backlog tickets: ${tickets.join(', ')}.
Read ${ROADMAP} for each ticket's spec (Objective/Files/Acceptance) and skim the real code under Vitrine/ to find which core files multiple tickets touch.
Return: (a) \`order\` = the tickets in safe build order (foundational types/files first — e.g. CS-050 settings schema versioning before tickets that add persisted fields; CS-020 ExportPreset before CS-030/CS-051; CS-036 design tokens before CS-037), each with isUI (true if it adds/changes visible UI) and a one-line rationale; (b) sharedFileHotspots = core files touched by 3+ tickets; (c) notes = brief feasibility caveats. Plan only — implement nothing.`,
  { phase: 'Plan', schema: PLAN_SCHEMA, label: 'plan' }
)

log(`Planned ${plan.order.length} tickets. Hotspots: ${(plan.sharedFileHotspots || []).join(', ') || 'none'}`)
if (mode === 'plan') {
  return { mode: 'plan', tickets, order: plan.order, sharedFileHotspots: plan.sharedFileHotspots, notes: plan.notes }
}

// =====================================================================
// Phase: Implement (SERIAL — tickets share core files, so no parallelism)
// =====================================================================
const results = []
for (const t of plan.order) {
  phase('Implement')

  // 1) Implement the ticket end to end, gated green. (free text + markers)
  const implText = await agent(
    `Implement backlog ticket ${t.id} ("${t.title}") for Vitrine. Read its full spec in ${ROADMAP} (Objective, Files, Design, Acceptance, Tests) and the relevant existing code, then implement it completely: create/modify the listed files, satisfy every Acceptance bullet, and add the unit tests the ticket calls for. ${GATE}
If the ticket is a Discovery/spike (e.g. CS-023), produce the documented finding + the minimal safe implementation it specifies instead of forcing a full build of an unsupported path.
${MARK_IMPL}`,
    { label: `impl:${t.id}`, phase: 'Implement' }
  )
  const status = parseStatus(implText)
  const filesChanged = parseFiles(implText)
  if (status !== 'green') {
    results.push({ id: t.id, title: t.title, isUI: t.isUI, status: 'blocked', notes: (implText || 'no output').slice(0, 600) })
    log(`⚠ ${t.id} blocked — skipping review/fix, continuing batch`)
    continue
  }
  log(`• ${t.id} implemented (${filesChanged.length} files); reviewing`)

  // 2) Swift 6 concurrency review + fix loop.
  const ccText = await agent(
    `${CONCURRENCY_PERSONA}\n\nReview ONLY the changes just made for ticket ${t.id}. Inspect ${filesChanged.length ? filesChanged.join(', ') : 'the working-tree diff (use git diff)'}. ${MARK_REVIEW}`,
    { label: `cc-review:${t.id}`, phase: 'Implement' }
  )
  if (parseFindings(ccText) > 0) {
    log(`  ${t.id}: ${parseFindings(ccText)} concurrency finding(s) → fixing`)
    await agent(
      `Fix these Swift 6 concurrency findings in ticket ${t.id}'s code, then re-verify green.\n\n${ccText}\n\n${GATE}`,
      { label: `cc-fix:${t.id}`, phase: 'Implement' }
    )
  }

  // 3) macOS HIG review + fix loop (UI tickets only).
  if (t.isUI) {
    const higText = await agent(
      `${HIG_PERSONA}\n\nReview ONLY the UI added/changed for ticket ${t.id}. Inspect ${filesChanged.length ? filesChanged.join(', ') : 'the working-tree diff'}. ${MARK_REVIEW}`,
      { label: `hig-review:${t.id}`, phase: 'Implement' }
    )
    if (parseFindings(higText) > 0) {
      log(`  ${t.id}: ${parseFindings(higText)} HIG finding(s) → fixing`)
      await agent(
        `Fix these macOS HIG findings in ticket ${t.id}'s UI, then re-verify green. Preserve accessibility identifiers the UI tests depend on.\n\n${higText}\n\n${GATE}`,
        { label: `hig-fix:${t.id}`, phase: 'Implement' }
      )
    }
  }

  // 4) Unit-test adequacy audit.
  const auditText = await agent(
    `Audit unit-test adequacy for ticket ${t.id}. Verify the new behavior is covered by meaningful assertions (not scaffolding) in the Swift Testing suite. If coverage is thin, add focused tests, then re-run. ${GATE}
${MARK_AUDIT}`,
    { label: `test-audit:${t.id}`, phase: 'Implement' }
  )

  results.push({
    id: t.id, title: t.title, isUI: t.isUI,
    status: 'green', // impl gate already passed
    filesChanged,
    audit: parseStatus(auditText),
    concurrency: parseFindings(ccText) > 0 ? 'fixed' : 'clean',
    hig: t.isUI ? 'reviewed' : 'n/a',
  })
  log(`✓ ${t.id} done (test-audit: ${parseStatus(auditText)})`)
}

const done = results.filter(r => r.status === 'green')
const blocked = results.filter(r => r.status === 'blocked')
log(`Implemented ${done.length}/${results.length} green; ${blocked.length} blocked`)

// =====================================================================
// Phase: Artifacts (review images on the Desktop for the human reviewer)
// =====================================================================
phase('Artifacts')
const artifacts = await agent(
  `Generate visual review artifacts into ${ARTIFACT_DIR} for human review. Steps:
1. mkdir -p ${ARTIFACT_DIR}/renders ${ARTIFACT_DIR}/ui
2. Run \`make test\` and capture stdout; the Sample gallery suite prints a line "GALLERY_DIR <path>" and "SAMPLE ..." lines. Copy every PNG from that GALLERY_DIR into ${ARTIFACT_DIR}/renders/ (these are the actual code→image product outputs across themes/fonts/languages/presets).
3. Best-effort live UI capture: \`make build\`, then \`open -n\` the built Vitrine.app with args \`--demo --open-editor --open-settings --snapshot-loop\`; wait ~20s; copy any PNGs from \`~/Library/Containers/app.vitrine/Data/tmp/vitrine-ui/\` into ${ARTIFACT_DIR}/ui/. If that yields nothing, note it — live window capture can fail headless and the main session will capture UI separately.
4. Write ${ARTIFACT_DIR}/README.txt listing what each subfolder contains and the ticket batch label "${label}".
Return a short summary: how many render PNGs and UI PNGs landed, and the absolute artifact path.`,
  { label: 'artifacts', phase: 'Artifacts' }
)

// =====================================================================
// Phase: Wrap-up (short, simplified commit message — NO AI attribution)
// =====================================================================
phase('Wrap-up')
const commitMessage = await agent(
  `Run \`git diff --stat\` and \`git status --short\` to see everything changed in this batch, plus this per-ticket result list:\n${JSON.stringify(results.map(r => ({ id: r.id, status: r.status })), null, 2)}\n
Write ONE short, simplified Conventional-Commits message (subject + up to 4 body bullets) summarizing what was implemented in batch "${label}". Reference the CS-IDs that landed green. Keep it tight.
HARD RULE: do NOT add any AI co-authorship or "generated-by" trailer (no "Co-Authored-By", no "Generated with Claude"). Plain message only. Return ONLY the commit message text.`,
  { label: 'commit-msg', phase: 'Wrap-up' }
)

return {
  label,
  implemented: done.map(r => r.id),
  blocked: blocked.map(r => ({ id: r.id, notes: r.notes })),
  artifactsDir: ARTIFACT_DIR,
  artifactsSummary: artifacts,
  commitMessage,
}
