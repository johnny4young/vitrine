# Vitrine — Competitive Feature Research (2026-06-15)

Survey of 20+ tools across **code-to-image** (ray.so, Carbon, Snappify, chalk.ist, CodeImage,
CodeSnap/Polacode, PostSpark, DotShare, CodeKeep), **screenshot beautifiers** (CleanShot X,
Xnapper, Shottr, Screely, Pika, Screenshot.rocks, Redactly, Snagit), and **dev-marketing /
mockup / video** (Mockuuups, DevMotion, Freeze, termshot, Tweetshots-style tools). 39 ideas,
each with inspiration, value to indie devs / dev-marketers, effort (S/M/L), and suggested tier.

**★** = already a parked/wishlist theme in Vitrine's own ROADMAP (low-risk to greenlight).

---

## A. Capture sources & input

1. **Terminal / ANSI output renderer** — paste raw shell output (ANSI codes) → styled terminal
   window image. *Freeze, termshot, yartsu.* Devs share CLI/test/build output constantly. **M ·
   Free** (a category no code-image rival owns well; needs no new permissions).
2. **Git-diff paste / side-by-side before→after** — paste a unified diff or two snippets →
   red/green or two-pane. *chalk.ist, Delta.* Vitrine has diff rendering; this adds the paste
   on-ramp + side-by-side. **S/M · Free.**
3. **GitHub Gist / permalink import** — paste a Gist or `blob/…#L10-L20` URL → pull code + range +
   filename. *Carbon.* **M · Free** (PRO for private repos).
4. **Multi-snippet canvas** — 2+ independent code/terminal cards on one canvas with arrows. *Snappify,
   CodeImage, chalk.ist.* The most-requested code-image power feature. **L · PRO.**
5. **Beautify-any-image input** — drop any PNG (UI, chart) → window chrome + gradient + padding +
   shadow, same engine as code. *Screely, Xnapper, Pika.* Unlocks the product-screenshot market
   **without Screen Recording** (sidesteps parked CS-046). **M · Free.**
6. **Clipboard-image auto-detect** — menu-bar quick action offers "Beautify clipboard image". *CleanShot,
   Pika.* **S · Free.**

## B. Editing / annotation

7. **Spotlight / dim-the-rest** — darken everything except a region/range. *CleanShot, Shottr.* Extends
   the existing code focus mode to any region. **S · Free.**
8. **Step-counter numbered badges** — auto-incrementing 1·2·3 circles for walkthroughs. *CleanShot,
   Snagit.* **S · Free.**
9. **Smart auto-redact (emails, API keys, tokens, IPs)** — scan rendered text, one-click blur of
   detected secrets/PII, on-device. *Xnapper, Redactly, Snagit Smart Redact.* Devs leak `.env`/bearer
   tokens constantly — safety + word-of-mouth, fits Vitrine's privacy story. **M · Free (basic) / PRO
   (custom rules).**
10. **Highlighter + smoothed freehand pencil** — beyond arrow/text/blur. *CleanShot, Shottr.* **M · Free.**
11. **Arrow styles (curved, elbow, weights)** — *CleanShot (4 styles), Snappify.* **S · Free.**
12. **Pixel ruler / dimension callouts + zoom loupe** — *Shottr, PixelSnap.* Design-handoff devs. **M · PRO.**
13. **Emoji / sticker layer** — 👀🔥✅ reactions. *Pika, Snappify.* Social engagement. **S · Free.**

## C. Output / export

14. **Animated GIF / MP4 reveal & diff** ★ — type-in / line-reveal / old→new morph clip. *Snappify,
    DevMotion.* On Vitrine's "later PRO" wishlist. Video crushes static engagement — biggest dev-
    marketing lever. **L · PRO.**
15. **Carousel / multi-slide export** ★ — split long code/tutorial into LinkedIn/Instagram carousel
    slides. *Postnitro, Snappify Slides.* Reuses multi-size plumbing; peak dev-marketing format. **M · PRO.**
16. **Auto line-wrap / auto-fit long lines** — soft-wrap with continuation indent instead of
    overflow/shrink. *Top real-world complaint about Carbon/ray.so.* **S/M · Free.**
17. **Copyable-text sidecar** — share image + raw source (alt text / `.txt` / `<pre>`) so viewers can
    copy. *Most-upvoted critique of every code-image tool.* Vitrine already has RTF/HTML clipboard. **S · Free.**
18. **Auto-balance / smart trim** — one click to even whitespace and center within padding. *Xnapper,
    CleanShot.* **M · Free.**
19. **WebP + size-optimized PNG** — smaller files for blogs/docs. *Freeze.* **S · Free.**
20. **Per-platform safe-area overlays + live line/char budget** — crop guides + "fits in N lines"
    indicator. *Pika/ray.so presets.* Prevents feed-crop reshares. **S · Free.**

## D. Sharing / automation

21. **One-click cloud share link** (optional expiry/password) — *CleanShot Cloud, Snappify.* The
    retention engine behind CleanShot; could ride parked hosted API CS-080. **L · PRO.**
22. **Embeddable interactive snippet (iframe)** — copy-enabled card for blogs/docs. *Snappify, CodeKeep.*
    Solves copyability + virality (every embed markets Vitrine). **L · PRO.**
23. **Watch-folder → auto-export** — drop code/image into a folder → auto-render with a preset. *Mockuuups
    batch; aligns CS-094.* **M · PRO.**
24. **Batch render from a manifest (CLI)** — `vitrine batch config.json`. *Snappify API, carbon-now-cli;
    extends the existing CLI; aligns CS-093/094.* **M · PRO.**
25. **Direct "Post to X / LinkedIn / Bluesky / Mastodon"** — share-sheet target with a pre-filled compose.
    *Carbon tweet button, Snappify socials.* Closes capture→post. **M · Free.**

## E. Branding / PRO

26. **Brand Kit presets — multiple switchable kits** ★ — *Screenshot Studio, Xnapper, Pika.* This is
    CS-092; the differentiator is *multiple* kits for agencies/multi-client. **M · PRO.**
27. **"via @handle" signature footer chip** — tasteful attribution bar (avatar + handle + site).
    *chalk.ist, ray.so, Carbon.* Free marketing on every shared image. **S · Free (handle) / PRO (logo+colors).**
28. **QR / link chip overlay** — QR or short-link badge (repo/article/profile). *Shottr, CTA patterns.*
    Conference slides + launch posts. **S · PRO.**
29. **Device & browser frames (image-input path)** — wrap dropped screenshots in MacBook/iPhone/browser
    chrome. *Pika, Screely, Mockuuups.* Serves product/App-Store assets. **M (browser) / L (device) ·
    Free + PRO.**
30. **Theme & preset marketplace / shareable links** — import community themes/presets via URL or a
    gallery. *ray.so partner themes, DotShare.* Vitrine has import/export presets + custom themes; this
    adds sharing/discovery + network effects. **M · Free (share) / PRO (team sync).**

## F. Collaboration

31. **Preset / Brand Kit team sync** — iCloud/file or hosted. *CleanShot teams, Snappify.* **M/L · PRO.**
32. **Shareable editable project file (`.vitrine`)** — re-openable project (source + config +
    annotations), Git-friendly, deterministic regeneration (fits the golden-image ethos). *CleanShot
    project format, DevMotion.* Vitrine already serializes `SnapshotConfig`. **S/M · Free.**

## G. Polish / UX

33. **Floating pinned snapshot (always-on-top)** — reference an error/design while coding. *CleanShot,
    Shottr.* **M · Free.**
34. **In-image OCR / copy-text-from-image (+ QR read)** — Vision-based; turn a screenshot of code back
    into text to re-render cleanly. *CleanShot, Shottr OCR.* **M · Free.**
35. **"I'm feeling lucky" theme/background shuffle** — one key cycles tasteful theme+gradient+font combos.
    *Carbon/ray.so quick theming.* Beats decision paralysis; delightful first run. **S · Free.**
36. **Re-export last N captures with a different preset/size** — from the menu bar, repurpose the same
    code as X image *and* OG card *and* slide. *CleanShot history; builds on Recents.* **S · Free.**

## H. AI-assisted (opt-in, no telemetry)

37. **AI alt-text / caption generator** — accessible alt text + suggested social caption/hashtags. *AI
    captioning tools.* Accessibility + saves post copy. **M · PRO (BYO key / on-device).**
38. **AI explain-this-code callouts** — auto-draft inline explanations for selected lines (you then
    edit). *Snappify AI direction.* Speeds tutorial creation. **M · PRO.**
39. **Smart title/filename/language inference** — suggest a header title + language badge from pasted
    content. *Xnapper; extends existing auto-detect.* **S · Free.**

---

## Top 10 highest-leverage

1. **Terminal/ANSI renderer (#1)** — opens a whole content category no rival owns; no new permissions.
2. **Animated GIF/MP4 reveal & diff (#14)** ★ — highest-engagement format; already a wishlist PRO item.
3. **Smart auto-redact secrets/PII (#9)** — safety + word-of-mouth; on-device fits the privacy story.
4. **Beautify-any-image input + frames (#5/#29)** — captures the product-screenshot market without
   Screen Recording (sidesteps parked CS-046).
5. **Carousel / multi-slide export (#15)** ★ — peak dev-marketing format; reuses multi-size plumbing.
6. **Multi-snippet canvas (#4)** — most-requested power feature; clear PRO differentiator.
7. **Auto line-wrap (#16) + copyable-text sidecar (#17)** — kills the two most-upvoted complaints about
   every code-image tool; cheap and high-trust.
8. **Brand Kit with multiple switchable kits (#26)** ★ — your CS-092 plus an agency twist.
9. **Watch-folder + manifest batch (#23/#24)** — productizes the CLI for content teams (CS-093/094).
10. **Cloud share + interactive embed (#21/#22)** — the virality/retention engine; every embed markets
    Vitrine (could ride hosted API CS-080).

**Roadmap alignment:** #2, #5, #8, #9, #10 map onto existing/parked themes — the "later PRO" wishlist
(carousel, custom sizes, extra templates, animated GIF/video), the PRO epic (CS-092/093/094), and the
parked hosted render API (CS-080). The image-input/device-frames idea (#5/#29) notably grows Vitrine into
the screenshot-beautifier market **without** triggering the Screen Recording permission that parked CS-046.

---

## Sources

ray.so · carbon-app/carbon (+ HN threads) · snappify.com/changelog · chalk.ist · app.codeimage.dev ·
CodeSnap/Polacode (GitHub issues) · postspark.app · charmbracelet/freeze · homeport/termshot · yartsu ·
dandavison/delta · codekeep.io · cleanshot.com/features · xnapper.com · shottr.cc · screely.com ·
pika.style · mockuuups.studio · devmotion.app · Redactly / Snagit Smart Redact · snap-tweet / tweetcapture.

---

# Batch 2 — 30 further ideas grounded in the current codebase (2026-07-02)

Each idea below is realizable with subsystems that already exist in the repo (CLI target,
App Intents, Services menu, Terminal grid, WebRendering multi-viewport, RecentsStore,
Brand Kit, `SnapshotConfig` serialization, deterministic SVG subset, xcstrings catalog).
Same key: effort (S/M/L) and suggested tier.

## I. Ecosystem & integrations (ride the existing CLI + deep links)

40. **`vitrine://` deep-link scheme** — encode a full `SnapshotConfig` in a URL so a snapshot
    is reproducible/shareable as a link; the on-ramp for every integration below. **S/M · Free.**
41. **Raycast extension** — "Beautify clipboard / selection" commands driving the CLI or deep
    links; ray.so users are exactly Vitrine's audience. **M · Free (OSS companion).**
42. **Xcode Source Editor Extension** — "Beautify Selection in Vitrine" straight from Xcode;
    reuses the editor handoff pasteboard IPC. **M · Free.**
43. **VS Code / Cursor extension** — send the current selection to Vitrine via deep link;
    the editor opens pre-filled. **M · Free (OSS companion).**
44. **Finder Quick Action + Share extension** — right-click any source file or image →
    rendered PNG; reuses FileInputLoader + the Services pipeline. **M · Free.**
45. **Stream Deck plugin** — one-key "beautify clipboard with preset N"; thin shell over the
    CLI. **S · PRO.**
46. **GitHub Action (macOS runner) for docs pipelines** — render snippets/terminal output at
    CI time with the existing `vitrine render`; publishes the CLI beyond the Mac. **M · Free.**
47. **`vitrine release-notes` subcommand** — render the top CHANGELOG entry as a social card
    for the release post; pure composition of existing parsers + SocialCardRenderer. **S · PRO.**

## J. New input types (reuse the render engine)

48. **asciinema `.cast` import** — pick a frame (or strip) from a recorded session and render
    it through the existing ANSI grid. **M · Free.**
49. **tmux / iTerm pane capture helper** — a `vitrine-pane` shell function that pipes the
    current pane's ANSI content in via the existing shell integration. **S · Free.**
50. **Jupyter notebook cell rendering** — paste/drop a `.ipynb`, choose a cell → code +
    output rendered together. **M · Free.**
51. **CSV/TSV/JSON table beautifier** — tabular clipboard data → a styled table card
    (monospace grid is already solved by the terminal renderer). **M · Free.**
52. **Auto-pretty-print before render** — one-click format for JSON/SQL/XML pastes so the
    image never ships minified one-liners. **S/M · Free.**
53. **Git-aware diff render in the CLI** — `vitrine render --git HEAD~1.. path/file.swift`
    emits the before→after diff image; extends the existing diff rendering. **M · PRO.**

## K. Editor power features

54. **Code folding / ellipsis ranges** — collapse selected line ranges into a `⋯` marker to
    fit long snippets without shrinking the font. **M · Free.**
55. **Snippet library** — named, searchable saved snippets (source + config), one step beyond
    Recents; `SnapshotConfig` serialization already exists. **M · Free (limit) / PRO (unlimited).**
56. **Command palette (⌘K)** — fuzzy actions for theme/font/background/export; the settings
    schema already enumerates every knob. **M · Free.**
57. **Re-render any Recent at a new size/preset** — Recents already stores the config; add
    "Export again as…" to the gallery context menu. **S · Free.**
58. **Drag-out export** — drag the live preview straight into Slack/Notion/Finder
    (`NSItemProvider`); complements Copy/Save. **S · Free.**
59. **Accessibility contrast audit** — warn when theme-on-background contrast falls below
    WCAG AA for the caption/watermark layers, with a one-click fix. **S/M · Free.**
60. **Color-blindness preview** — simulate deuteranopia/protanopia over the live preview so
    shared teaching material is checked before posting. **M · Free.**

## L. Output & automation

61. **Multi-page PDF for long code** — paginate past a height budget with header/footer and
    line-number continuity; extends the existing color-managed PDF path. **M · PRO.**
62. **HEIC export** — ImageIO already writes it; smaller files for docs sites that accept it.
    **S · Free.**
63. **Copy as Markdown/HTML embed block** — image + fenced source + alt text in one clipboard
    flavor for READMEs and blogs; extends RichPasteboard. **S · Free.**
64. **Copy as `data:` URI** — self-contained embed for HTML emails/single-file docs. **S · Free.**
65. **Honest SVG for terminal captures** — the terminal grid is deterministic geometry +
    monospace text runs, so it can serialize to real `<text>`/`<rect>` SVG the same way
    `VectorTemplateSVG` handles template backgrounds. **L · PRO.**
66. **Menu-bar "render clipboard with preset…" submenu** — quick capture through any saved
    destination preset without opening the editor. **S · Free.**
67. **"Render Terminal Output" App Intent** — Shortcuts automation for the ANSI path (the
    render service and intent scaffolding already exist). **S · Free.**
68. **Scheduled watch-clipboard mode** — opt-in: when the clipboard turns into code, pulse
    the menu-bar icon offering a one-click render (no polling daemon; NSPasteboard
    changeCount on activation). **M · Free.**
69. **More locales (fr, de, pt-BR, ja)** — the 570-key xcstrings catalog ships at 100% for
    en/es and LocalizationTests already enforce coverage; each locale is mechanical. **M · Free.**

## Batch-2 top 5 by leverage

1. **Deep-link scheme (#40)** — unlocks #41–#45 almost for free and makes configs shareable.
2. **Raycast + VS Code extensions (#41/#43)** — meets developers inside the tools they
   already use; pure companions, no app changes beyond #40.
3. **Snippet library + re-render Recents (#55/#57)** — turns one-shot captures into a
   reusable asset library (retention).
4. **Copy as Markdown/HTML embed (#63)** — the cheapest answer to the "viewers can't copy
   the code" complaint, compounding the existing text sidecar.
5. **asciinema import (#48)** — extends the terminal moat no competitor owns.
