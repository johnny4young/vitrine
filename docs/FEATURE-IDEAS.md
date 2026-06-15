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
