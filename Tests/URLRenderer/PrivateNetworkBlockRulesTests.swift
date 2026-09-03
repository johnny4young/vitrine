import Foundation
import Testing
import VitrineDomain

@testable import Vitrine

@Suite("URL capture private-subresource rules")
struct PrivateNetworkBlockRulesTests {
    @Test func everyRuleBlocksEveryWebKitResourceType() throws {
        let source = try PrivateNetworkBlockRules.encodedContentRuleList(
            allowsLoopback: false)
        let data = try #require(source.data(using: .utf8))
        let rules = try #require(
            try JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(!rules.isEmpty)
        for rule in rules {
            let action = try #require(rule["action"] as? [String: Any])
            let trigger = try #require(rule["trigger"] as? [String: Any])
            #expect(action["type"] as? String == "block")
            #expect(trigger["url-filter"] as? String != nil)
            #expect(trigger["url-filter-is-case-sensitive"] as? Bool == false)
            // WebKit treats an omitted resource-type as every category. This is
            // what covers images, CSS, scripts, child documents, fetch/XHR, fonts,
            // media, WebSockets, and future categories without a brittle allowlist.
            #expect(trigger["resource-type"] == nil)
        }
    }

    @Test(
        "Default policy blocks representative private subresources",
        arguments: [
            ("image", "http://127.0.0.1:43127/image.png"),
            ("stylesheet", "https://192.168.1.4/style.css"),
            ("script", "https://user@10.0.0.5/app.js"),
            ("iframe", "http://172.16.0.4/frame"),
            ("fetch", "https://169.254.169.254/latest/meta-data"),
            ("websocket", "wss://[::1]:43127/socket"),
            ("multicast DNS", "https://printer.local/status"),
            ("reserved IPv4", "http://240.0.0.1/resource"),
            ("decimal private IPv4", "http://167772161/resource"),
            ("hex private IPv4", "http://0x0a000001/resource"),
            ("short private IPv4", "http://10.1/resource"),
            ("octal-looking private IPv4", "http://012.0.0.1/resource"),
            ("private IPv6", "https://[fd00::1234]/resource"),
            ("mapped IPv6", "https://[::ffff:192.168.1.1]/resource"),
            ("hex-mapped IPv6", "https://[::ffff:c0a8:101]/resource"),
            ("full-form hex-mapped IPv6", "https://[0:0:0:0:0:ffff:c0a8:101]/resource"),
            ("full-form dotted-mapped IPv6", "https://[0:0:0:0:0:ffff:192.168.1.1]/resource"),
            ("hex-mapped loopback", "https://[::ffff:7f00:1]/resource"),
            ("IETF protocol assignments", "https://192.0.0.8/resource"),
            ("TEST-NET-1", "https://192.0.2.1/resource"),
            ("6to4 relay anycast", "https://192.88.99.1/resource"),
            ("benchmarking /15", "https://198.19.0.1/resource"),
            ("TEST-NET-2", "https://198.51.100.7/resource"),
            ("TEST-NET-3", "https://203.0.113.9/resource"),
            ("mapped TEST-NET-2", "https://[::ffff:198.51.100.7]/resource"),
        ])
    func defaultPolicyBlocksPrivateResource(_ fixture: (kind: String, url: String)) throws {
        #expect(
            try matches(fixture.url, allowsLoopback: false),
            "\(fixture.kind) must be blocked before it reaches the network")
    }

    @Test func loopbackOptInRemovesOnlyStrictLoopbackRules() throws {
        for url in [
            "http://localhost:3000/image.png",
            "https://dev.localhost/style.css",
            "http://127.0.0.2:5173/app.js",
            "http://127.1/frame",
            "http://0177.1/data",
            "http://0x7f000001/data",
            "http://2130706433/data",
            "http://2130706432/data",
            "http://2147483647/data",
            "https://[::1]:43127/socket",
            "https://[::ffff:127.0.0.1]/asset",
            "https://[::ffff:7f00:1]/asset",
            "https://[::ffff:7fff:ffff]/asset",
            "https://[0:0:0:0:0:ffff:7f00:1]/asset",
            "https://[0:0:0:0:0:ffff:127.0.0.1]/asset",
        ] {
            #expect(try !matches(url, allowsLoopback: true), "\(url) is explicit loopback")
            #expect(try matches(url, allowsLoopback: false), "\(url) is blocked by default")
        }

        for url in [
            "https://dev.local/style.css",
            "https://10.0.0.5/app.js",
            "https://100.64.0.1/data",
            "https://169.254.169.254/meta",
            "https://172.31.255.255/frame",
            "https://192.168.1.1/image",
            "http://167772161/data",
            "http://0x0a000001/data",
            "http://10.1/data",
            "http://012.0.0.1/data",
            "https://[fe80::1]/asset",
            "https://[fd00::1]/asset",
            "https://[::ffff:c0a8:101]/asset",
            "https://[::ffff:a00:1]/asset",
            "https://[0:0:0:0:0:ffff:c0a8:101]/asset",
        ] {
            #expect(
                try matches(url, allowsLoopback: true),
                "\(url) must remain blocked after loopback opt-in")
        }
    }

    @Test func publicLookalikesAreNotOvermatched() throws {
        for url in [
            "https://example.com/127.0.0.1/image.png",
            "https://localhost.example.com/style.css",
            "https://10.0.0.1.example.com/app.js",
            "https://128.0.0.1/frame",
            "https://example.localhost.example/fetch",
            "wss://socket.example.com/private",
            "https://[2606:4700::6810:84e5]/asset",
            "https://[2001:db8::ffff:1:2]/asset",
            // Neighbours of the RFC 6890 blocks: the rules must stop exactly at the edges.
            "https://192.0.1.1/asset",
            "https://192.0.3.1/asset",
            "https://192.88.98.1/asset",
            "https://198.17.255.255/asset",
            "https://198.20.0.1/asset",
            "https://198.51.99.1/asset",
            "https://203.0.112.1/asset",
            "https://203.0.114.1/asset",
        ] {
            #expect(try !matches(url, allowsLoopback: false), "\(url) is public")
        }
    }

    @Test func ruleListIdentifiersKeepLoopbackPoliciesSeparate() {
        #expect(
            PrivateNetworkBlockRules.identifier(allowsLoopback: false)
                == "vitrine-block-private-v1")
        #expect(
            PrivateNetworkBlockRules.identifier(allowsLoopback: true)
                == "vitrine-block-private-allow-loopback-v1")
        #expect(
            PrivateNetworkBlockRules.identifier(allowsLoopback: false)
                != PrivateNetworkBlockRules.identifier(allowsLoopback: true))
    }

    @Test func loopbackOptInUsesNarrowExceptionsAfterConservativeBlocks() {
        let rules = PrivateNetworkBlockRules.rules(allowsLoopback: true)
        let actionTypes = rules.map(\.action.type)
        #expect(actionTypes.contains("block"))
        #expect(actionTypes.contains("ignore-previous-rules"))
        #expect(actionTypes.last == "ignore-previous-rules")
    }

    private func matches(_ url: String, allowsLoopback: Bool) throws -> Bool {
        var isBlocked = false
        for rule in PrivateNetworkBlockRules.rules(allowsLoopback: allowsLoopback) {
            let expression = try NSRegularExpression(
                pattern: rule.trigger.urlFilter,
                options: rule.trigger.urlFilterIsCaseSensitive ? [] : [.caseInsensitive])
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            guard expression.firstMatch(in: url, range: range) != nil else { continue }
            isBlocked = rule.action.type == "block"
        }
        return isBlocked
    }
}

@MainActor
@Suite("URL capture private-subresource rules compile in WebKit")
struct PrivateNetworkBlockRuleCompilationTests {
    @Test func defaultAndLoopbackListsCompileSeparately() async throws {
        let strict = try await URLSnapshotEngine.privateNetworkBlockList(allowsLoopback: false)
        let loopback = try await URLSnapshotEngine.privateNetworkBlockList(allowsLoopback: true)
        #expect(strict.identifier == PrivateNetworkBlockRules.identifier(allowsLoopback: false))
        #expect(loopback.identifier == PrivateNetworkBlockRules.identifier(allowsLoopback: true))
        #expect(strict.identifier != loopback.identifier)
    }
}

extension PrivateNetworkBlockRulesTests {
    /// The domain classifier (`PrivateHostPolicy`, used for the navigation URL) and
    /// these content rules (used for every subresource) encode the same address
    /// space twice — once as Swift, once as Safari content-blocker regexes — so they
    /// can drift silently. Walk one representative literal per range, plus the
    /// boundary neighbours, and require both layers to agree.
    @Test func contentRulesAgreeWithTheDomainClassifierForCanonicalIPv4Literals() throws {
        let privateLiterals = [
            "0.1.2.3", "10.1.2.3", "100.64.1.2", "100.127.254.1", "127.0.0.1",
            "169.254.169.254", "172.16.1.2", "172.31.254.1", "192.0.0.8", "192.0.2.1",
            "192.88.99.1", "192.168.1.2", "198.18.1.2", "198.19.1.2", "198.51.100.1",
            "203.0.113.1", "224.0.0.1", "239.255.255.250", "240.0.0.1", "255.255.255.255",
        ]
        let publicLiterals = [
            "1.1.1.1", "8.8.8.8", "93.184.216.34", "100.63.255.255", "100.128.0.1",
            "128.0.0.1", "172.15.255.255", "172.32.0.1", "192.0.1.1", "192.0.3.1",
            "192.88.98.1", "192.167.255.255", "192.169.0.1", "198.17.255.255",
            "198.20.0.1", "198.51.99.1", "198.51.101.1", "203.0.112.1", "203.0.114.1",
            "223.255.255.255",
        ]
        for literal in privateLiterals {
            #expect(
                PrivateHostPolicy.isPrivateLocalhost(host: literal),
                "classifier must treat \(literal) as private")
            #expect(
                try matches("https://\(literal)/asset", allowsLoopback: false),
                "content rules must block \(literal)")
            #expect(
                try matches("https://[::ffff:\(literal)]/asset", allowsLoopback: false),
                "content rules must block the mapped form of \(literal)")
        }
        for literal in publicLiterals {
            #expect(
                !PrivateHostPolicy.isPrivateLocalhost(host: literal),
                "classifier must treat \(literal) as public")
            #expect(
                try !matches("https://\(literal)/asset", allowsLoopback: false),
                "content rules must not block \(literal)")
        }
    }
}
