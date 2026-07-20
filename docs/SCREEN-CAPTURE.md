# Arbitrary Screen and Window Capture

## Decision

Vitrine does not capture arbitrary displays or other applications' windows. It
renders content it owns—code, terminal output, HTML, webpages, social cards, and
imported images—and therefore does not request Screen Recording permission.

This is a product and trust boundary, not an unimplemented feature. Capturing the
desktop would move Vitrine into a different product category, expose unrelated
private content, add a recurring macOS permission prompt, and complicate App Store
review. Those costs are not justified when users can import an image they captured
with the system tool they already trust.

## Supported alternative

Users can capture a window or region with macOS, then paste, drop, or open the
finished image in Vitrine. The app can frame, annotate, redact, and export that image
through the same local pipeline as its other inputs. This provides the useful part
of a screenshot-beautification workflow without access to the live screen.

## Rejected implementations

- **ScreenCaptureKit:** technically correct for a future first-party capture tool,
  but it carries the full Screen Recording permission and product-positioning cost.
- **Quartz display/window capture APIs:** legacy APIs such as
  `CGWindowListCreateImage` are deprecated and inconsistent with the project's
  modern-API policy.
- **AVFoundation screen input:** `AVCaptureScreenInput` is designed for recording,
  not a one-shot image, and carries the same permission cost.
- **Accessibility scraping:** brittle, inappropriate for image capture, and a worse
  trust trade-off.
- **Hosted screen capture:** incompatible with Vitrine's local-first privacy promise.

## Conditions for reconsideration

Reconsideration would require strong, measured demand that cannot be served by image
import. Any change must be evaluated separately from the shipping target and must:

1. use ScreenCaptureKit and `SCScreenshotManager`, never legacy capture APIs;
2. demonstrate denial, revocation, and recurring-consent behavior under App Sandbox;
3. scope capture to an explicit window or display and exclude Vitrine's own UI;
4. update the privacy manifest, App Store disclosures, entitlements, and
   [`PERMISSIONS.md`](PERMISSIONS.md) before product integration;
5. include a clear user-facing explanation of the permission and its risks.

Until those conditions are met, the no-Screen-Recording posture is intentional and
should remain enforced by tests.

## References

- [`PROJECT.md`](PROJECT.md)
- [`PERMISSIONS.md`](PERMISSIONS.md)
- [Apple ScreenCaptureKit documentation](https://developer.apple.com/documentation/screencapturekit)
- [Apple SCScreenshotManager documentation](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
