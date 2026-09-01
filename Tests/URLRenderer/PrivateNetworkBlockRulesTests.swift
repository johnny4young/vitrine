import Foundation
import Testing

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
