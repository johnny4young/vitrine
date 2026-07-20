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

## Web capture boundary

A webpage is loaded locally in WebKit. Vitrine does not send the URL or rendered output
to a screenshot service. Remote capture is available only in a build with the network
client entitlement and after a first-use disclosure. The URL pipeline rejects malformed,
non-HTTP, local, private, and unsafe redirect destinations. A default-off setting may
allow only this Mac's loopback interface (`localhost`, IPv4 `127/8`, IPv6 `::1`, and
mapped loopback) for development servers; multicast-DNS `.local`, LAN, link-local,
metadata, and every other private/reserved destination remain blocked. The same policy
is applied to the initial URL and redirects. Downloads and decoded data are bounded.

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
