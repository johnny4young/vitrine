import Foundation
import Testing
import VitrineDomain

/// The pre-resolution host classifier, exercised hostlessly. The app-level suites cover
/// the URL surface and the WebKit content rules; this one pins the address-space table
/// itself so a range cannot be lost when the policy moves again.
@Suite("Private host policy")
struct PrivateHostPolicyTests {
    @Test(
        "Every RFC 1918 / RFC 6890 non-global IPv4 range is classified as private",
        arguments: [
            ("this network", "0.1.2.3"),
            ("private 10/8", "10.1.2.3"),
            ("shared address space", "100.64.0.1"),
            ("shared address space (top)", "100.127.255.254"),
            ("loopback", "127.0.0.1"),
            ("link-local", "169.254.169.254"),
            ("private 172.16/12", "172.16.0.1"),
            ("private 172.16/12 (top)", "172.31.255.254"),
            ("IETF protocol assignments", "192.0.0.8"),
            ("TEST-NET-1", "192.0.2.1"),
            ("6to4 relay anycast", "192.88.99.1"),
            ("private 192.168/16", "192.168.1.1"),
            ("benchmarking (low)", "198.18.0.1"),
            ("benchmarking (high)", "198.19.255.254"),
            ("TEST-NET-2", "198.51.100.7"),
            ("TEST-NET-3", "203.0.113.9"),
            ("multicast", "224.0.0.251"),
            ("reserved", "240.0.0.1"),
            ("broadcast", "255.255.255.255"),
        ])
    func nonGlobalIPv4IsPrivate(_ fixture: (kind: String, host: String)) {
        #expect(
            PrivateHostPolicy.isPrivateLocalhost(host: fixture.host),
            Comment(rawValue: fixture.kind))
        #expect(
            PrivateHostPolicy.isPrivateLocalhost(host: "::ffff:\(fixture.host)"),
            "\(fixture.kind) via IPv4-mapped IPv6")
        #expect(
            PrivateHostPolicy.isRefusedHost(fixture.host, allowLoopback: true)
                == !PrivateHostPolicy.isLoopbackHost(host: fixture.host),
            "loopback opt-in must release only loopback")
    }

    @Test(
        "Neighbours of every special-purpose block stay public",
        arguments: [
            "1.1.1.1", "8.8.8.8", "93.184.216.34", "100.63.255.255", "100.128.0.1",
            "128.0.0.1", "172.15.255.255", "172.32.0.1", "192.0.1.1", "192.0.3.1",
            "192.88.98.1", "192.88.100.1", "192.167.255.255", "192.169.0.1",
            "198.17.255.255", "198.20.0.1", "198.51.99.1", "198.51.101.1", "203.0.112.1",
            "203.0.114.1", "223.255.255.255",
        ])
    func globalIPv4StaysPublic(_ host: String) {
        #expect(!PrivateHostPolicy.isPrivateLocalhost(host: host))
        #expect(!PrivateHostPolicy.isRefusedHost(host, allowLoopback: false))
    }
    // MARK: - IPv4 addresses hidden inside IPv6 literals

    /// Two transition formats carry an IPv4 address inside an IPv6 literal, so a private
    /// destination can be written entirely in IPv6 and never reach the IPv4 table. The
    /// asymmetry this closes: the IPv4 table already refuses the 6to4 relay anycast
    /// prefix, while a 6to4 address wrapping a private target was classified public.
    @Test(
        "6to4 and NAT64 literals wrapping a private IPv4 address are private",
        arguments: [
            ("6to4 loopback", "2002:7f00:1::"),
            ("6to4 link-local metadata", "2002:a9fe:a9fe::"),
            ("6to4 private 10/8", "2002:a00:1::"),
            ("6to4 private 192.168/16", "2002:c0a8:101::"),
            ("NAT64 loopback", "64:ff9b::7f00:1"),
            ("NAT64 link-local metadata", "64:ff9b::a9fe:a9fe"),
            ("NAT64 private 172.16/12", "64:ff9b::ac10:1"),
            // The local-use translation prefix is refused whatever it wraps, so a
            // private tail is covered here and a public one below.
            ("NAT64 local-use private 192.168/16", "64:ff9b:1::c0a8:1"),
            ("NAT64 local-use, IPv4 at a site-chosen offset", "64:ff9b:1:c0a8:1::"),
        ])
    func embeddedPrivateIPv4IsPrivate(_ fixture: (kind: String, host: String)) {
        #expect(
            PrivateHostPolicy.isPrivateLocalhost(host: fixture.host),
            Comment(rawValue: fixture.kind))
        #expect(
            PrivateHostPolicy.isPrivateLocalhost(host: "[\(fixture.host)]"),
            "\(fixture.kind) in URL bracket form")
    }

    /// The same prefixes wrapping a public address stay public: this refuses an embedded
    /// private destination, not the transition mechanism. IANA registers both `2002::/16`
    /// and the NAT64 well-known `64:ff9b::/96` as globally reachable, so refusing them
    /// wholesale would block a legitimate capture.
    @Test(
        "6to4 and NAT64 literals wrapping a public IPv4 address stay public",
        arguments: ["2002:808:808::", "2002:5db8:d822::", "64:ff9b::808:808"])
    func embeddedPublicIPv4StaysPublic(host: String) {
        #expect(!PrivateHostPolicy.isPrivateLocalhost(host: host))
    }

    /// The local-use translation prefix is the exception, and not because of what it
    /// wraps. IANA registers `64:ff9b:1::/48` as special-purpose and not globally
    /// reachable, so — like every other non-global range this policy refuses — no literal
    /// under it can be a public origin, whatever its tail decodes to. RFC 6052 also lets
    /// the site choose where the IPv4 address sits inside it, so there is no fixed offset
    /// a pre-resolution classifier could read even if it wanted to.
    @Test(
        "every local-use NAT64 literal is refused, public-looking tails included",
        arguments: [
            "64:ff9b:1::808:808",  // a public tail in the well-known layout
            "64:ff9b:1:808:808::",  // the same address at a different site offset
            "64:ff9b:1::",  // no tail at all
            "64:ff9b:1:ffff:ffff:ffff:ffff:ffff",
        ])
    func theLocalUseTranslationPrefixIsRefusedWhole(host: String) {
        #expect(PrivateHostPolicy.isPrivateLocalhost(host: host))
        #expect(PrivateHostPolicy.isPrivateLocalhost(host: "[\(host)]"))
    }

    /// A wrapped loopback address is refused even with the local-address opt-in on. The
    /// opt-in exists to reach a development server on this Mac; a tunnelled spelling does
    /// not resolve to the loopback interface, so releasing it would widen the opt-in past
    /// what the user agreed to.
    @Test func theLocalAddressOptInDoesNotReleaseTunnelledLoopback() {
        for host in ["2002:7f00:1::", "64:ff9b::7f00:1"] {
            #expect(!PrivateHostPolicy.isLoopbackHost(host: host))
            #expect(PrivateHostPolicy.isRefusedHost(host, allowLoopback: true))
        }
    }

}
