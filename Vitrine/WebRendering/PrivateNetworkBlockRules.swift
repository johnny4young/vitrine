import Foundation

/// WebKit content-blocker rules that keep URL-capture subresources away from
/// literal local, private, link-local, metadata, multicast, and reserved hosts.
///
/// The initial URL and every frame navigation still pass through
/// `WebSnapshotConfig.isRefusedHost`. These rules are the separate, load-bearing
/// layer for resource types a navigation delegate never sees: images, style
/// sheets, scripts, fonts, media, `fetch`/XHR, WebSockets, and related requests.
/// Omitting `resource-type` from every trigger deliberately applies the block to
/// all WebKit resource categories.
///
/// Content blockers match the request URL, not the address returned by DNS. A
/// public hostname that later resolves or rebinds to a private address therefore
/// remains a DNS/TOCTOU residual; this literal-host backstop must not be described
/// as resolver-level network isolation.
enum PrivateNetworkBlockRules {
    struct Rule: Encodable, Equatable {
        struct Trigger: Encodable, Equatable {
            let urlFilter: String
            let urlFilterIsCaseSensitive = false

            enum CodingKeys: String, CodingKey {
                case urlFilter = "url-filter"
                case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            }
        }

        struct Action: Encodable, Equatable {
            let type: String

            static let block = Action(type: "block")
            static let ignorePreviousRules = Action(type: "ignore-previous-rules")
        }

        let trigger: Trigger
        let action: Action
    }

    /// Distinct identifiers prevent WebKit from reusing the default rule list for
    /// the narrower, explicit loopback opt-in policy (or vice versa).
    static func identifier(allowsLoopback: Bool) -> String {
        allowsLoopback
            ? "vitrine-block-private-allow-loopback-v1"
            : "vitrine-block-private-v1"
    }

    /// The source passed to `WKContentRuleListStore`. `JSONEncoder` handles regex
    /// escaping, and `String(decoding:as:)` cannot fail for the encoder's UTF-8
    /// bytes. The function remains throwing so an encoder failure is propagated
    /// into the engine's fail-closed isolation error rather than ignored.
    static func encodedContentRuleList(allowsLoopback: Bool) throws -> String {
        let data = try JSONEncoder().encode(rules(allowsLoopback: allowsLoopback))
        return String(decoding: data, as: UTF8.self)
    }

    static func rules(allowsLoopback: Bool) -> [Rule] {
        let blockingRules = (privateFilters + loopbackFilters).map {
            Rule(trigger: .init(urlFilter: $0), action: .block)
        }
        guard allowsLoopback else { return blockingRules }

        // Content blockers have no negative lookahead. Keep the conservative
        // numeric-host backstop and append narrowly scoped exceptions for actual
        // loopback spellings only when the user enabled local development capture.
        return blockingRules
            + loopbackFilters.map {
                Rule(trigger: .init(urlFilter: $0), action: .ignorePreviousRules)
            }
    }

    /// `http(s)` covers document and ordinary subresources; `ws(s)` covers
    /// script-created WebSockets. Optional user information is consumed before
    /// matching the host so `https://user@127.0.0.1/` cannot evade the rule.
    // Safari content-blocker regular expressions intentionally omit alternation.
    // Emit one filter per scheme family instead of using a disjunction that
    // `WKContentRuleListStore` would reject at compile time.
    private static let schemeAndAuthorityPrefixes = [
        #"^https?://([^/?#]*@)?"#,
        #"^wss?://([^/?#]*@)?"#,
    ]
    private static let hostBoundary = #"[:/?#]"#

    private static func hostFilters(_ hostPattern: String) -> [String] {
        schemeAndAuthorityPrefixes.map { $0 + hostPattern + hostBoundary }
    }

    /// Private/reserved hosts that remain blocked even when the user explicitly
    /// permits this Mac's loopback interface for a local development server.
    private static let privateHostPatterns: [String] = [
        // Multicast-DNS names. The label-aware expression rejects `service.local`
        // but not a public lookalike such as `notlocal.example`.
        #"([^./?#]+\.)*local\.?"#,

        // Common canonical IPv4 literals. The final host boundary prevents a
        // public lookalike such as `10.0.0.1.example.com` from matching.
        #"0\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"10\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"100\.6[4-9]\.[0-9]+\.[0-9]+"#,
        #"100\.[7-9][0-9]\.[0-9]+\.[0-9]+"#,
        #"100\.1[01][0-9]\.[0-9]+\.[0-9]+"#,
        #"100\.12[0-7]\.[0-9]+\.[0-9]+"#,
        #"169\.254\.[0-9]+\.[0-9]+"#,
        #"172\.1[6-9]\.[0-9]+\.[0-9]+"#,
        #"172\.2[0-9]\.[0-9]+\.[0-9]+"#,
        #"172\.3[01]\.[0-9]+\.[0-9]+"#,
        #"192\.168\.[0-9]+\.[0-9]+"#,
        // RFC 6890 special-purpose blocks that are non-global but not "private" in
        // the RFC 1918 sense: IETF protocol assignments, the three TEST-NETs, the
        // benchmarking /15, and the deprecated 6to4 relay anycast prefix. Mirrors
        // `PrivateHostPolicy.isPrivateIPv4`; the parity test keeps them aligned.
        #"192\.0\.0\.[0-9]+"#,
        #"192\.0\.2\.[0-9]+"#,
        #"192\.88\.99\.[0-9]+"#,
        #"198\.1[89]\.[0-9]+\.[0-9]+"#,
        #"198\.51\.100\.[0-9]+"#,
        #"203\.0\.113\.[0-9]+"#,
        #"22[4-9]\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"23[0-9]\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"24[0-9]\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"25[0-5]\.[0-9]+\.[0-9]+\.[0-9]+"#,

        // Legacy resolver spellings can hide a private IPv4 address in a decimal
        // integer, hexadecimal value, shortened dotted value, or octal-looking
        // component. Block those ambiguous forms conservatively. The loopback
        // subset receives explicit `ignore-previous-rules` exceptions only after
        // the user opts in.
        #"[0-9][0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?"#,
        #"0x[0-9a-f]+"#,
        #"[0-9]+\.[0-9]+"#,
        #"[0-9]+\.[0-9]+\.[0-9]+"#,
        #"[0-9a-fx.]*0x[0-9a-fx.]*"#,
        #"0[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"#,
        #"[0-9]+\.0[0-9]+\.[0-9]+\.[0-9]+"#,
        #"[0-9]+\.[0-9]+\.0[0-9]+\.[0-9]+"#,
        #"[0-9]+\.[0-9]+\.[0-9]+\.0[0-9]+"#,

        // IPv6 unspecified, link/site-local, unique-local, and multicast literals.
        // Web URLs bracket IPv6 hosts, making the authority boundary unambiguous.
        #"\[::(%[a-z0-9._~-]+)?\]"#,
        #"\[0:0:0:0:0:0:0:0(%[a-z0-9._~-]+)?\]"#,
        #"\[f[cd][0-9a-f:%.]*\]"#,
        #"\[fe[89abcdef][0-9a-f:%.]*\]"#,
        #"\[ff[0-9a-f:%.]*\]"#,

        // IPv4-mapped private IPv6 literals WebKit may preserve in URL form.
        #"\[::ffff:0\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:10\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:100\.6[4-9]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:100\.[7-9][0-9]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:100\.1[01][0-9]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:100\.12[0-7]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:169\.254\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:172\.1[6-9]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:172\.2[0-9]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:172\.3[01]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:192\.168\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:192\.0\.0\.[0-9]+\]"#,
        #"\[::ffff:192\.0\.2\.[0-9]+\]"#,
        #"\[::ffff:192\.88\.99\.[0-9]+\]"#,
        #"\[::ffff:198\.1[89]\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:198\.51\.100\.[0-9]+\]"#,
        #"\[::ffff:203\.0\.113\.[0-9]+\]"#,
        #"\[::ffff:22[4-9]\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:23[0-9]\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:24[0-9]\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        #"\[::ffff:25[0-5]\.[0-9]+\.[0-9]+\.[0-9]+\]"#,

        // IPv4-mapped IPv6 with hexadecimal tails. WHATWG URL parsing — which
        // WebKit follows — serializes even a dotted mapped literal back to hex
        // groups, so `[::ffff:c0a8:101]` (192.168.1.1) is the spelling a request
        // URL actually carries. Enumerating the private ranges in hex is
        // error-prone and a public subresource host in this exotic spelling is
        // vanishingly rare, so block the whole hex-tail family conservatively,
        // matching the ambiguous-IPv4 stance above. Both canonical spellings are
        // covered (WHATWG reduces every other compression to the first). The
        // loopback subset receives its exception only after the user opts in.
        #"\[::ffff:[0-9a-f]+:[0-9a-f]+\]"#,
        #"\[0:0:0:0:0:ffff:[0-9a-f]+:[0-9a-f]+\]"#,
        #"\[0:0:0:0:0:ffff:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
    ]

    private static let privateFilters = privateHostPatterns.flatMap { hostFilters($0) }

    /// Strict loopback patterns removed only by the explicit loopback setting.
    /// Alongside canonical forms, cover the legacy numeric spellings macOS accepts
    /// and the host validator already recognizes. The integer expression is
    /// intentionally conservative because decimal-integer hosts are obsolete and
    /// ambiguous; blocking an unusual public integer spelling is safer than
    /// letting a private resolver-equivalent spelling reach the local machine.
    private static let loopbackHostPatterns: [String] = [
        #"([^./?#]+\.)*localhost\.?"#,
        #"127\.[0-9]+(\.[0-9]+(\.[0-9]+)?)?"#,
        #"0177\.[0-9]+(\.[0-9]+(\.[0-9]+)?)?"#,
        #"0x7f[0-9a-f]*"#,
        // Decimal integers in 127.0.0.0/8: 2130706432...2147483647.
        // Separate range fragments avoid alternation and bounded repetition,
        // neither of which Safari's content-blocker regex dialect accepts.
        #"213070643[2-9]"#,
        #"21307064[4-9][0-9]"#,
        #"2130706[5-9][0-9][0-9]"#,
        #"213070[7-9][0-9][0-9][0-9]"#,
        #"21307[1-9][0-9][0-9][0-9][0-9]"#,
        #"2130[89][0-9][0-9][0-9][0-9][0-9]"#,
        #"213[1-9][0-9][0-9][0-9][0-9][0-9][0-9]"#,
        #"214[0-6][0-9][0-9][0-9][0-9][0-9][0-9]"#,
        #"2147[0-3][0-9][0-9][0-9][0-9][0-9]"#,
        #"21474[0-7][0-9][0-9][0-9][0-9]"#,
        #"214748[0-2][0-9][0-9][0-9]"#,
        #"2147483[0-5][0-9][0-9]"#,
        #"21474836[0-3][0-9]"#,
        #"214748364[0-7]"#,
        #"\[::1(%[a-z0-9._~-]+)?\]"#,
        #"\[0:0:0:0:0:0:0:1(%[a-z0-9._~-]+)?\]"#,
        #"\[::ffff:127\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
        // Hexadecimal-mapped loopback: 127.0.0.0/8 always maps to a first hex
        // group of 7f00–7fff, so these exceptions cannot reach past loopback.
        #"\[::ffff:7f[0-9a-f][0-9a-f]:[0-9a-f]+\]"#,
        #"\[0:0:0:0:0:ffff:7f[0-9a-f][0-9a-f]:[0-9a-f]+\]"#,
        #"\[0:0:0:0:0:ffff:127\.[0-9]+\.[0-9]+\.[0-9]+\]"#,
    ]

    private static let loopbackFilters = loopbackHostPatterns.flatMap { hostFilters($0) }
}
