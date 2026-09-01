# Rendering Architecture

Vitrine uses one local rendering contract for the app, command line, Services,
Shortcuts, and App Intents. Inputs are normalized into typed models, rendered on the
Mac, color-managed, and exported without a hosted dependency.

## Supported inputs

| Input | Local implementation | Network required |
| --- | --- | --- |
| Code and diff | Highlightr plus SwiftUI canvas | No |
| Terminal and recordings | ANSI/VT grid plus SwiftUI canvas | No |
| Social card | SwiftUI templates | No |
| Imported image | ImageIO plus SwiftUI framing and annotations | No |
| HTML | Isolated offscreen WebKit view | No; remote requests are blocked |
| Webpage URL | Offscreen WebKit view with strict URL validation | Yes, in the direct-download channel |

Every surface ultimately produces the same rendered image types and uses the same
ImageIO/PDF export paths. This keeps app, CLI, automation, and batch output consistent.
Golden-image fixtures and performance tests protect that contract.

## Resource and failure boundary

Raster output is never allocated from untrusted or naturally derived dimensions without a
shared `RenderBudget` preflight. Preview and export have separate limits, and each check
includes logical width/height, scale, total pixels, and an estimate of concurrently live
buffers. Arithmetic is overflow-safe. Web Snapshot also clamps full-page height before
asking WebKit for pixels and validates the actual returned image again before composition.

App, CLI, App Intents, batch, social-card, comparison-board, Web responsive-board,
pasteboard, and file adapters preserve four typed outcomes: too large, allocation failed,
encoding failed, and cancelled. This makes an extreme request an actionable error rather
than a blank artifact, partial success, or abrupt process exit. PDF remains vector output;
raster previews and embedded images still pass through the applicable bitmap budget.

## Web capture boundary

A webpage is loaded locally in WebKit. Vitrine does not send the URL or rendered output
to a screenshot service. Remote capture is available only in a build with the network
client entitlement and after a first-use disclosure. The URL pipeline rejects malformed,
non-HTTP, local, private, and unsafe redirect destinations. A default-off setting may
allow only this Mac's loopback interface (`localhost` and its reserved subdomains,
IPv4 `127/8`, IPv6 `::1`, and mapped loopback) for development servers;
multicast-DNS `.local`, LAN, link-local, metadata, and every other private/reserved
destination remain blocked. The same policy is applied to the initial URL and frame
redirects. A compiled WebKit content rule separately blocks literal-private image, CSS,
script, iframe, fetch/XHR, WebSocket, and other subresource URLs before they reach the
network. Downloads and decoded data are bounded.

This is layered literal-host filtering, not resolver isolation. WebKit content rules see
the request URL rather than the IP address returned by DNS, so a public hostname that
resolves or rebinds to a private address remains a DNS/TOCTOU residual. Clean-Mac QA
proves zero requests to a literal loopback probe and does not claim to close that residual.

Pasted HTML is different: it uses a non-persistent WebKit data store and a compiled
content rule that blocks remote subresources, navigation, and script-initiated requests.
It remains offline even when the direct-download app has network access for other
features.

## Hosted rendering

A hosted renderer is not part of Vitrine's shipping architecture. It would require a
separate service, security boundary, privacy policy, abuse controls, retention policy,
and operational ownership. The native core must never depend on one.

A future service should be considered only after measured demand for non-Mac consumers
or public HTTP automation. It must start as a separate product decision with SSRF
protection, strict isolation, bounded resources, and no reuse of private local content by
default. Until then, the CLI and macOS automation surfaces are the supported programmatic
interfaces.

## Related documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md)
- [`PERMISSIONS.md`](PERMISSIONS.md)
- [`PROJECT.md`](PROJECT.md)
- [`SCREEN-CAPTURE.md`](SCREEN-CAPTURE.md)
