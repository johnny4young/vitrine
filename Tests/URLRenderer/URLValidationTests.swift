import Foundation
import Testing

@testable import Vitrine

// MARK: - URL validation

@Suite("URL capture validation")
struct URLValidationTests {
    @Test func httpAndHttpsURLsAreAccepted() throws {
        let http = try #require(URL(string: "http://example.com"))
        let https = try #require(URL(string: "https://example.com/path?q=1#frag"))
        #expect(try WebSnapshotConfig.validate(captureURL: http) == http)
        #expect(try WebSnapshotConfig.validate(captureURL: https) == https)
    }

    @Test func schemeMatchingIsCaseInsensitive() throws {
        // A pasted URL may carry an upper-cased scheme; it is still a web URL.
        let upper = try #require(URL(string: "HTTPS://example.com"))
        #expect(try WebSnapshotConfig.validate(captureURL: upper) == upper)
    }

    @Test func fileURLsAreRejected() throws {
        let file = try #require(URL(string: "file:///etc/passwd"))
        #expect(throws: URLValidationError.unsupportedScheme("file")) {
            try WebSnapshotConfig.validate(captureURL: file)
        }
    }

    @Test func dataURLsAreRejected() throws {
        // `data:` is a non-web scheme, refused by name; it never loads, which is the
        // guarantee that matters.
        let data = try #require(URL(string: "data:text/html,<b>x</b>"))
        #expect(throws: URLValidationError.unsupportedScheme("data")) {
            try WebSnapshotConfig.validate(captureURL: data)
        }
    }

    @Test func javascriptURLsAreRejected() throws {
        // A `javascript:` URL is a non-web scheme, refused by name; it never executes.
        let js = try #require(URL(string: "javascript:alert(1)"))
        #expect(throws: URLValidationError.unsupportedScheme("javascript")) {
            try WebSnapshotConfig.validate(captureURL: js)
        }
    }

    @Test func otherSchemesAreRejectedAsUnsupported() throws {
        // A scheme that does parse a host (e.g. ftp) is refused as an unsupported
        // scheme, naming the scheme but never the URL.
        let ftp = try #require(URL(string: "ftp://files.example.com/archive.zip"))
        #expect(throws: URLValidationError.unsupportedScheme("ftp")) {
            try WebSnapshotConfig.validate(captureURL: ftp)
        }
    }

    @Test func malformedStringsAreRejected() {
        // Empty, scheme-only, and host-less strings cannot form a loadable URL.
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "")
        }
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "https://")
        }
        #expect(throws: URLValidationError.malformed) {
            try WebSnapshotConfig.validate(captureURLString: "not a url")
        }
    }

    @Test func localhostHostsAreRejected() throws {
        for raw in [
            "http://localhost/admin",
            "http://localhost:3000",
            "http://127.0.0.1:8080",
            "http://127.5.4.3/",
            "http://[::1]:9000",
            "http://0.0.0.0:5000",
            "http://myservice.local/status",
        ] {
            let url = try #require(URL(string: raw), "fixture \(raw) must parse")
            #expect(
                throws: URLValidationError.privateLocalhost,
                "\(raw) must be refused as private localhost"
            ) {
                try WebSnapshotConfig.validate(captureURL: url)
            }
        }
    }

    @Test func loopbackCanBeAllowedWithoutOpeningLocalNetworks() throws {
        for raw in [
            "http://localhost:3000", "http://localhost./admin", "http://127.0.0.1:8080",
            "http://127.0.0.2:5173", "http://127.1", "http://0177.1",
            "http://0x7f000001", "http://2130706433", "http://[::1]:9000",
            "http://[::ffff:127.0.0.1]",
        ] {
            let url = try #require(URL(string: raw), "fixture \(raw) must parse")
            #expect(throws: Never.self, "\(raw) is this Mac's loopback interface") {
                try WebSnapshotConfig.validate(captureURL: url, allowLoopback: true)
            }
        }
    }

    @Test func loopbackOptionNeverAllowsMulticastDNSOrPrivateRanges() throws {
        for raw in [
            "http://dev.local/status", "http://192.168.1.1/", "http://10.0.0.5:8080/",
            "http://172.16.0.1/", "http://100.64.0.1/",
            "http://169.254.169.254/latest/meta-data/", "http://[fe80::1]/",
            "http://[fec0::1]/", "http://[fd00::1]/", "http://[ff02::1]/", "http://[::]/",
            "http://0.0.0.0:5000/", "http://224.0.0.251/", "http://240.0.0.1/",
        ] {
            let url = try #require(URL(string: raw), "fixture \(raw) must parse")
            #expect(throws: URLValidationError.privateLocalhost, "\(raw) must stay blocked") {
                try WebSnapshotConfig.validate(captureURL: url, allowLoopback: true)
            }
        }
    }

    @Test func loopbackPredicateIsAStrictSubsetOfTheDefaultBlocklist() {
        for host in [
            "localhost", "localhost.", "127.0.0.1", "127.1", "0177.1", "0x7f000001",
            "2130706433", "::1", "[::1]", "::ffff:127.0.0.1", "::ffff:127.1",
        ] {
            #expect(WebSnapshotConfig.isLoopbackHost(host: host), "\(host) must be loopback")
            #expect(WebSnapshotConfig.isPrivateLocalhost(host: host))
        }

        for host in [
            "dev.local", "service.local.", "192.168.1.1", "10.0.0.5", "169.254.169.254",
            "fe80::1", "fd00::1", "0.0.0.0", "::ffff:192.168.1.1", "example.com",
            "localhost.example.com",
        ] {
            #expect(!WebSnapshotConfig.isLoopbackHost(host: host), "\(host) is not loopback")
        }
    }

    @Test func textValidationUsesTheSameLoopbackPolicy() throws {
        #expect(throws: URLValidationError.privateLocalhost) {
            try WebSnapshotConfig.validate(captureURLString: " http://localhost:3000\n")
        }
        let url = try WebSnapshotConfig.validate(
            captureURLString: " http://localhost:3000\n", allowLoopback: true)
        #expect(url.host == "localhost")
    }

    @Test func configCarriesTheLoopbackChoiceIntoRedirectPolicy() throws {
        let url = try #require(URL(string: "http://localhost:3000"))
        let config = try WebSnapshotConfig(captureURL: url, allowsLoopbackCapture: true)
        #expect(config.allowsLoopbackCapture)
        #expect(!WebSnapshotConfig.isRefusedHost("localhost", allowLoopback: true))
        #expect(WebSnapshotConfig.isRefusedHost("localhost", allowLoopback: false))
        #expect(WebSnapshotConfig.isRefusedHost("dev.local", allowLoopback: true))
        #expect(WebSnapshotConfig.isRefusedHost("169.254.169.254", allowLoopback: true))
    }

    @Test func resolverEquivalentLocalhostSpellingsAreRejectedByHostGuard() {
        // macOS accepts several IPv4 literal spellings that are not four dotted
        // decimal octets. The SSRF guard must reject them before WebKit hands them to
        // the resolver.
        for host in [
            "localhost.",
            "service.local.",
            "127.1",
            "0177.1",
            "0x7f000001",
            "2130706433",
            "::ffff:127.0.0.1",
            "::ffff:127.1",
            "fe90::1",
            "fd00::1",
        ] {
            #expect(
                WebSnapshotConfig.isPrivateLocalhost(host: host),
                "\(host) must be refused as local/private")
        }
    }

    @Test func publicHostsThatMerelyContainLoopbackTextAreAllowed() throws {
        // The localhost guard must not over-match: a real public host whose name
        // merely contains "localhost" or starts past the loopback block still loads.
        let lookalike = try #require(URL(string: "https://localhost.example.com/page"))
        #expect(try WebSnapshotConfig.validate(captureURL: lookalike) == lookalike)
        let notLoopback = try #require(URL(string: "https://128.0.0.1/page"))
        #expect(try WebSnapshotConfig.validate(captureURL: notLoopback) == notLoopback)
        #expect(!WebSnapshotConfig.isPrivateLocalhost(host: "1.2.3"))
    }

    @Test func validatingTextTrimsSurroundingWhitespace() throws {
        // A pasted URL often carries a trailing newline; validation trims before
        // parsing so the clean URL is what would load.
        let url = try WebSnapshotConfig.validate(captureURLString: "  https://example.com/x  \n")
        #expect(url == (try #require(URL(string: "https://example.com/x"))))
    }

    @Test func validationErrorsAreDistinctAndCarryNoURL() {
        // The typed-error contract: the cases are not interchangeable, and the
        // associated value is a scheme token, never the URL.
        #expect(URLValidationError.malformed != .privateLocalhost)
        #expect(URLValidationError.unsupportedScheme("file") != .unsupportedScheme("data"))
        #expect(URLValidationError.unsupportedScheme("file") != .malformed)
        #expect(URLValidationError.malformed == .malformed)
    }

    @Test func everyValidationErrorHasAStableNonPIIDiagnosticReason() {
        // The diagnostic label names the refusal, never the URL, and is distinct per
        // case so logs are filterable.
        let reasons = [
            URLValidationError.malformed.diagnosticReason,
            URLValidationError.unsupportedScheme("file").diagnosticReason,
            URLValidationError.privateLocalhost.diagnosticReason,
        ]
        #expect(Set(reasons).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.isEmpty })
        #expect(URLValidationError.privateLocalhost.diagnosticReason == "private-localhost")
        #expect(
            URLValidationError.unsupportedScheme("file").diagnosticReason
                == "unsupported-scheme-file")
    }
}
