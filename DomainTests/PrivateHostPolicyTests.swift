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
}
