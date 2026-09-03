import Foundation
import VitrineDomain

// MARK: - URL validation

/// Why a URL was refused for capture, as a typed error rather than a silent
/// fallback. Each case names a distinct, non-PII reason so the first-use
/// UI can explain the refusal and tests can assert the exact cause — the value
/// never carries the rejected URL.
enum URLValidationError: Error, Equatable {
    /// The string could not be parsed into a URL, or the URL had no scheme/host —
    /// a malformed input that cannot be loaded.
    case malformed

    /// The scheme is not `http` or `https`. Carries the offending scheme (a fixed,
    /// non-PII token like `file` or `javascript`) so the refusal is explainable
    /// without echoing the URL.
    case unsupportedScheme(String)

    /// The URL points at a local, private, link-local, or reserved host. Loopback
    /// remains available only through the explicit, default-off loopback option.
    case privateLocalhost
}

extension WebSnapshotConfig {
    /// Validates a candidate capture URL, returning a normalized `http`/`https` URL
    /// or throwing a typed `URLValidationError`.
    ///
    /// The rules, in order, enforce the URL safety contract:
    ///
    /// 1. A scheme that is present but not `http`/`https` is rejected as
    ///    `unsupportedScheme`, naming the scheme — this is the explicit refusal for
    ///    `file:`, `ftp:`, and any `file:///path` URL whose host is empty (the scheme
    ///    is the meaningful reason, not the missing host).
    /// 2. Otherwise the URL must parse and carry both a scheme and a non-empty host
    ///    (`malformed` otherwise) — this rejects empty input, scheme-only strings,
    ///    and `javascript:`/`data:` payloads that carry no host.
    /// 3. The host must not be local/private (`privateLocalhost` otherwise). A
    ///    default-off option may lift this rule only for the strict loopback subset.
    ///
    /// Checking the scheme before the host means a non-web scheme is always reported
    /// as such, even when it happens to have no host (e.g. `file:///etc/hosts`),
    /// which is the more useful refusal. The check is pure (a
    /// function of the URL alone, with no network access), so it is fully
    /// unit-testable without a web view.
    static func validate(captureURL: URL, allowLoopback: Bool = false) throws -> URL {
        // A present, non-web scheme is refused as such first — including a
        // `file:///path` URL with an empty host — so the reported reason names the
        // scheme rather than a missing host.
        if let scheme = captureURL.scheme?.lowercased(), !allowedSchemes.contains(scheme) {
            throw URLValidationError.unsupportedScheme(scheme)
        }

        // From here the URL is either schemeless or a web URL; it must carry a
        // scheme and a non-empty host to be loadable.
        guard captureURL.scheme != nil, let host = captureURL.host, !host.isEmpty else {
            throw URLValidationError.malformed
        }

        if isRefusedHost(host, allowLoopback: allowLoopback) {
            throw URLValidationError.privateLocalhost
        }

        return captureURL
    }

    /// Validates a candidate capture URL supplied as text. Trims surrounding
    /// whitespace (a pasted URL often carries a trailing newline) before parsing,
    /// and surfaces `malformed` for a string `URL` cannot parse — so the textual
    /// entry point shares the exact same rules as the `URL` one.
    static func validate(captureURLString text: String, allowLoopback: Bool = false) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw URLValidationError.malformed
        }
        return try validate(captureURL: url, allowLoopback: allowLoopback)
    }

    /// The only schemes a URL capture may use. Deliberately limited to the two web
    /// schemes; everything else — `file:`, `data:`, `javascript:`, `blob:`, `ftp:`
    /// is refused unless a future explicit local-file mode is added.
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// Whether `host` is local, private, or link-local — refused for capture as the
    /// SSRF defense. Covers `localhost`/`.local` (including trailing-dot
    /// FQDN spellings), resolver-equivalent IPv4 literals such as `127.1`,
    /// `0177.1`, `0x7f000001`, and `2130706433`, `0.0.0.0/8`, IPv4 loopback
    /// `127.0.0.0/8`, the RFC1918 private ranges (`10/8`, `172.16/12`, `192.168/16`),
    /// CGNAT/Tailscale `100.64.0.0/10`, link-local `169.254.0.0/16` (including the
    /// `169.254.169.254` cloud-metadata endpoint), multicast `224.0.0.0/4`, reserved
    /// `240.0.0.0/4` + broadcast, IPv6 unspecified `::`, loopback `::1`, link-local
    /// `fe80::/10`, deprecated site-local `fec0::/10`, unique-local `fc00::/7`, multicast
    /// `ff00::/8`, and IPv4-mapped IPv6 (`::ffff:a.b.c.d`). A public hostname or address
    /// passes through.
    ///
    /// This is a pre-resolution host blocklist, so **DNS rebinding** (a public hostname
    /// that resolves to a private address) is a known residual risk; the first-use consent
    /// disclosure is the primary mitigation for that vector, and the page is loaded locally
    /// in WebKit with a compiled content-rule blocklist.
    nonisolated static func isPrivateLocalhost(host: String) -> Bool {
        PrivateHostPolicy.isPrivateLocalhost(host: host)
    }

    /// The single host policy shared by entry validation and redirect guards.
    /// Opting in removes the refusal only for this Mac's loopback interface; `.local`,
    /// LAN, link-local, CGNAT, metadata, and reserved addresses remain blocked.
    nonisolated static func isRefusedHost(_ host: String, allowLoopback: Bool) -> Bool {
        PrivateHostPolicy.isRefusedHost(host, allowLoopback: allowLoopback)
    }

    /// Whether `host` names this Mac's loopback interface specifically. This is a
    /// strict subset of the default blocklist: `localhost` and its reserved
    /// subdomains, IPv4 `127/8`, IPv6 `::1`, and IPv4-mapped loopback.
    /// Multicast-DNS `.local` names are deliberately not included because they can
    /// identify other devices on the local network.
    nonisolated static func isLoopbackHost(host: String) -> Bool {
        PrivateHostPolicy.isLoopbackHost(host: host)
    }
}
