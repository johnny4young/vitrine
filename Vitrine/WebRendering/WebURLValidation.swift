import Foundation

#if canImport(Darwin)
    import Darwin
#endif

// MARK: - URL validation

/// Why a URL was refused for capture, as a typed error rather than a silent
/// fallback (CS-043). Each case names a distinct, non-PII reason so the first-use
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

    /// The URL points at the local machine (localhost, a loopback IP, or a
    /// `.local` host). Capturing a private localhost service is refused until a
    /// future explicit local mode exists.
    case privateLocalhost
}

extension WebSnapshotConfig {
    /// Validates a candidate capture URL, returning a normalized `http`/`https` URL
    /// or throwing a typed `URLValidationError`.
    ///
    /// The rules, in order, implement the CS-043 acceptance criteria:
    ///
    /// 1. A scheme that is present but not `http`/`https` is rejected as
    ///    `unsupportedScheme`, naming the scheme — this is the explicit refusal for
    ///    `file:`, `ftp:`, and any `file:///path` URL whose host is empty (the scheme
    ///    is the meaningful reason, not the missing host).
    /// 2. Otherwise the URL must parse and carry both a scheme and a non-empty host
    ///    (`malformed` otherwise) — this rejects empty input, scheme-only strings,
    ///    and `javascript:`/`data:` payloads that carry no host.
    /// 3. The host must not be the local machine (`privateLocalhost` otherwise) —
    ///    `localhost`, loopback IPv4/IPv6, and `.local` hosts are refused so a
    ///    private localhost service is never captured by default.
    ///
    /// Checking the scheme before the host means a non-web scheme is always reported
    /// as such, even when it happens to have no host (e.g. `file:///etc/hosts`),
    /// which is the more useful, acceptance-aligned refusal. The check is pure (a
    /// function of the URL alone, with no network access), so it is fully
    /// unit-testable without a web view.
    static func validate(captureURL: URL) throws -> URL {
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

        if isPrivateLocalhost(host: host) {
            throw URLValidationError.privateLocalhost
        }

        return captureURL
    }

    /// Validates a candidate capture URL supplied as text. Trims surrounding
    /// whitespace (a pasted URL often carries a trailing newline) before parsing,
    /// and surfaces `malformed` for a string `URL` cannot parse — so the textual
    /// entry point shares the exact same rules as the `URL` one.
    static func validate(captureURLString text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            throw URLValidationError.malformed
        }
        return try validate(captureURL: url)
    }

    /// The only schemes a URL capture may use. Deliberately limited to the two web
    /// schemes; everything else — `file:`, `data:`, `javascript:`, `blob:`, `ftp:`
    /// — is refused unless a future explicit local-file mode is added.
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// Whether `host` is local, private, or link-local — refused for capture as the
    /// SSRF defense for CS-043. Covers `localhost`/`.local` (including trailing-dot
    /// FQDN spellings), resolver-equivalent IPv4 literals such as `127.1`,
    /// `0177.1`, `0x7f000001`, and `2130706433`, `0.0.0.0/8`, IPv4 loopback
    /// `127.0.0.0/8`, the RFC1918 private ranges (`10/8`, `172.16/12`, `192.168/16`),
    /// CGNAT/Tailscale `100.64.0.0/10`, link-local `169.254.0.0/16` (including the
    /// `169.254.169.254` cloud-metadata endpoint), reserved `240.0.0.0/4` + broadcast,
    /// IPv6 loopback `::1`, link-local `fe80::/10`, unique-local `fc00::/7`, and
    /// IPv4-mapped IPv6 (`::ffff:a.b.c.d`). A public hostname or address passes through.
    ///
    /// This is a pre-resolution host blocklist, so **DNS rebinding** (a public hostname
    /// that resolves to a private address) is a known residual risk; the first-use consent
    /// disclosure is the primary mitigation for that vector, and the page is loaded locally
    /// in WebKit with a compiled content-rule blocklist.
    nonisolated static func isPrivateLocalhost(host: String) -> Bool {
        let lowered = host.lowercased()
        // Strip the brackets WebKit/URL use around an IPv6 literal host.
        var bare = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        // A fully-qualified localhost spelling (`localhost.` / `service.local.`)
        // still resolves locally. Strip only terminal DNS-root dots; interior dots
        // remain untouched, so `localhost.example.com` stays a public hostname.
        while bare.count > 1, bare.hasSuffix(".") {
            bare.removeLast()
        }

        // Hostnames that always resolve to the local machine / link.
        if bare == "localhost" { return true }
        if bare == "local" || bare.hasSuffix(".local") { return true }

        // IPv6 loopback / link-local / unique-local literals. Strip a zone id
        // (`fe80::1%lo0`) before parsing; it names an interface, not a remote host.
        let addressLiteral = bare.split(separator: "%", maxSplits: 1).first.map(String.init) ?? bare
        if let ipv6 = ipv6Bytes(from: addressLiteral) {
            if isLoopbackIPv6(ipv6) { return true }
            if isPrivateIPv6(ipv6) { return true }
            if isIPv4MappedIPv6(ipv6) {
                return isPrivateIPv4(Array(ipv6.suffix(4)))
            }
        }

        // IPv4-mapped IPv6 with a legacy IPv4 tail (`::ffff:127.1`) is not accepted
        // by `inet_pton(AF_INET6)` on every platform, so reduce it manually too. Use the
        // zone-stripped `addressLiteral` so `::ffff:127.1%lo0` still reduces to its IPv4 tail.
        let ipv4 =
            addressLiteral.hasPrefix("::ffff:")
            ? String(addressLiteral.dropFirst("::ffff:".count)) : addressLiteral
        guard let octets = ipv4Octets(from: ipv4) else { return false }
        return isPrivateIPv4(octets)
    }

    /// Parses strict and legacy resolver-equivalent IPv4 literals without DNS.
    ///
    /// `inet_aton` intentionally accepts the same shorthand/numeric forms macOS will
    /// resolve for WebKit (`127.1`, `0177.1`, `0x7f000001`, `2130706433`). That keeps
    /// the pre-load SSRF guard aligned with the resolver without issuing a network
    /// lookup for public hostnames.
    nonisolated private static func ipv4Octets(from host: String) -> [UInt8]? {
        #if canImport(Darwin)
            var address = in_addr()
            guard host.withCString({ inet_aton($0, &address) }) != 0 else { return nil }
            let value = UInt32(bigEndian: address.s_addr)
            return [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff),
            ]
        #else
            let octets = host.split(separator: ".").compactMap { UInt8($0) }
            return octets.count == 4 ? octets : nil
        #endif
    }

    nonisolated private static func ipv6Bytes(from host: String) -> [UInt8]? {
        #if canImport(Darwin)
            var address = in6_addr()
            guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
                return nil
            }
            return withUnsafeBytes(of: address) { Array($0) }
        #else
            return nil
        #endif
    }

    nonisolated private static func isLoopbackIPv6(_ bytes: [UInt8]) -> Bool {
        bytes.count == 16 && bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    }

    nonisolated private static func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        // Link-local fe80::/10 and unique-local fc00::/7.
        if bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 { return true }
        if (bytes[0] & 0xfe) == 0xfc { return true }
        return false
    }

    nonisolated private static func isIPv4MappedIPv6(_ bytes: [UInt8]) -> Bool {
        bytes.count == 16
            && bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xff
            && bytes[11] == 0xff
    }

    nonisolated private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (0, _): return true  // 0.0.0.0/8 "this host" (a 0.x address can route locally)
        case (10, _): return true  // 10.0.0.0/8 private
        case (100, 64...127): return true  // 100.64.0.0/10 CGNAT / Tailscale (RFC 6598)
        case (127, _): return true  // 127.0.0.0/8 loopback
        case (169, 254): return true  // 169.254/16 link-local + cloud metadata
        case (172, 16...31): return true  // 172.16.0.0/12 private
        case (192, 168): return true  // 192.168.0.0/16 private
        case (240...255, _): return true  // 240.0.0.0/4 reserved + 255.255.255.255 broadcast
        default: return false
        }
    }
}
