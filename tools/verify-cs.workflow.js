// Ultracode workflow: adversarially verify that every CS-0xx ticket meets its
// objective in the Vitrine codebase + tests. One read-only agent per ticket,
// run in parallel; each must cite concrete evidence (file:line and/or a test
// name) to mark a ticket "meets". Run via the Workflow tool ({scriptPath}).
export const meta = {
  name: "verify-cs",
  description: "Adversarially verify every CS ticket against the Vitrine code + tests",
  phases: [{ title: "Verify", detail: "one read-only agent per ticket" }],
}

const REPO = "/Users/johnny4young/Personal/github/vitrine"

const TICKETS = [
  { id: "CS-001", objective: "Menu-bar app: MenuBarExtra(.menu) + LSUIElement=YES (no Dock).", files: "Vitrine/App/VitrineApp.swift, Vitrine/App/AppDelegate.swift, Vitrine/Resources/Info.plist" },
  { id: "CS-002", objective: "Configurable global hotkey whose action (quick capture vs open editor) is user-selectable.", files: "Vitrine/Models/GlobalShortcuts.swift, Vitrine/App/AppDelegate.swift, Vitrine/Settings/AppSettings.swift, Vitrine/Settings/GeneralSettingsView.swift" },
  { id: "CS-003", objective: "NSTextView editor with live syntax highlight (~100ms debounce), Tab=4 spaces, no autocorrect.", files: "Vitrine/Editor/CodeEditorView.swift, Vitrine/Editor/Debouncer.swift, Vitrine/Editor/HighlightManager.swift" },
  { id: "CS-004", objective: "Language auto-detect (weighted scoring, Go not misread as Swift), manual picker, recents-first order.", files: "Vitrine/Editor/LanguageDetector.swift, Vitrine/Settings/AppSettings.swift (recentLanguages/orderedLanguages), Vitrine/Editor/EditorView+Toolbar.swift" },
  { id: "CS-005", objective: "SnapshotCanvas is a WYSIWYG SwiftUI view feeding ImageRenderer.", files: "Vitrine/Canvas/SnapshotCanvas.swift, Vitrine/Canvas/BackgroundView.swift, Vitrine/Canvas/WindowChrome.swift, Vitrine/Export/ExportManager.swift" },
  { id: "CS-006", objective: "Customization: theme, padding(16-64), font size(10-20), background, chrome toggle, shadow toggle.", files: "Vitrine/Settings/StyleSettingsView.swift, Vitrine/Settings/SettingsSharedControls.swift, Vitrine/Models/SnapshotConfig.swift (showShadow/effectiveShadowRadius)" },
  { id: "CS-007", objective: "Retina PNG export to clipboard and file via ImageRenderer + ImageIO (no NSBitmapImageRep).", files: "Vitrine/Export/ExportManager.swift" },
  { id: "CS-008", objective: "macOS Share Sheet wired into the editor toolbar.", files: "Vitrine/Export/ShareManager.swift, Vitrine/Editor/EditorView+Toolbar.swift, Vitrine/Export/ExportManager.swift (renderNSImage)" },
  { id: "CS-009", objective: "Menu with Recents▸ (real) and Theme▸ submenus, quick capture, and user feedback on outcome.", files: "Vitrine/MenuBar/MenuBarContent.swift, Vitrine/MenuBar/QuickCapture.swift, Vitrine/Feedback/Notifier.swift" },
  { id: "CS-010", objective: "Settings window with General/Style/Output/Input/About panes and a live preview in Style.", files: "Vitrine/Settings/SettingsWindow.swift, Vitrine/Settings/SettingsRootView.swift, Vitrine/Settings/GeneralSettingsView.swift, Vitrine/Settings/StyleSettingsView.swift, Vitrine/Settings/OutputSettingsView.swift, Vitrine/Settings/InputSettingsView.swift, Vitrine/Settings/AboutSettingsView.swift" },
  { id: "CS-011", objective: "PrivacyInfo.xcprivacy (no tracking, only UserDefaults) + sandbox without network.client.", files: "Vitrine/Resources/PrivacyInfo.xcprivacy, Vitrine/Resources/Vitrine.entitlements, Tests/PrivacyTests.swift" },
  { id: "CS-012", objective: "Release pipeline: release.yml + build-dmg.sh + Homebrew cask + RELEASING.md, signing gated on secrets.", files: ".github/workflows/release.yml, scripts/build-dmg.sh, packaging/Casks/vitrine.rb, docs/RELEASING.md" },
  { id: "CS-013", objective: "RecentsStore: last 10 captures persisted to UserDefaults, newest-first, deduped; reopenable.", files: "Vitrine/State/RecentsStore.swift, Vitrine/Models/Capture.swift, Vitrine/MenuBar/MenuBarContent.swift" },
  { id: "CS-014", objective: "Launch at login via SMAppService (not deprecated SMLoginItemSetEnabled).", files: "Vitrine/Settings/LaunchAtLogin.swift, Vitrine/Settings/GeneralSettingsView.swift" },
  { id: "CS-015", objective: "Swift Testing target with meaningful tests; make test runs green.", files: "project.yml (VitrineTests), Makefile, Tests/CoreTests.swift, Tests/FeatureTests.swift, Tests/PrivacyTests.swift" },
  { id: "CS-016", objective: "User feedback for quick-capture outcomes via UserNotifications; outcome->message is a pure tested function.", files: "Vitrine/Feedback/Notifier.swift, Tests/FeatureTests.swift" },
  { id: "CS-017", objective: "Reproducible custom app icon generator + populated AppIcon.appiconset (all macOS slots).", files: "scripts/make-appicon.swift, Vitrine/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json, Makefile (icon)" },
  { id: "CS-018", objective: "CI workflow runs make lint + make build + make test on macOS for push/PR.", files: ".github/workflows/ci.yml" },
]

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    id: { type: "string" },
    status: { type: "string", enum: ["meets", "partial", "fails"] },
    evidence: { type: "string", description: "Concrete file:line refs and/or test names that prove it" },
    gaps: { type: "string", description: "What is missing to fully meet the objective, or 'none'" },
  },
  required: ["id", "status", "evidence", "gaps"],
}

phase("Verify")

const verdicts = await parallel(
  TICKETS.map((t) => () =>
    agent(
      `You are adversarially verifying ticket ${t.id} of the Vitrine macOS app (Swift 6, repo at ${REPO}).\n\n` +
        `OBJECTIVE: ${t.objective}\n` +
        `LIKELY FILES: ${t.files}\n` +
        `Also look under Tests/ for a covering test.\n\n` +
        `Read the actual files (use absolute paths under ${REPO}). Decide honestly whether the implementation ` +
        `truly meets the objective. Mark status "meets" ONLY when you can cite concrete evidence: specific ` +
        `file:line references and/or the name of a test in Tests/ that exercises it. Use "partial" if it is ` +
        `wired but incomplete, "fails" if absent or broken. Be skeptical — do not give the benefit of the doubt. ` +
        `Do NOT run builds or tests; verify by reading. Return {id:"${t.id}", status, evidence, gaps}.`,
      { label: `verify:${t.id}`, phase: "Verify", schema: SCHEMA, agentType: "Explore" }
    )
  )
)

const clean = verdicts.filter(Boolean)
const tally = { meets: 0, partial: 0, fails: 0 }
for (const v of clean) tally[v.status] = (tally[v.status] || 0) + 1
const problems = clean.filter((v) => v.status !== "meets")

log(`Verified ${clean.length}/${TICKETS.length} tickets — meets:${tally.meets} partial:${tally.partial} fails:${tally.fails}`)

return { tally, problems, verdicts: clean }
