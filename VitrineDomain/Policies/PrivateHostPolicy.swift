import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Pure, pre-resolution classification for hosts that must not be treated as public origins.
///
/// This policy deliberately performs no DNS lookup. It covers local hostnames, resolver-equivalent
/// IPv4 literals, private/link-local/reserved address space, and IPv4-mapped IPv6. Callers that load
/// network content must still mitigate DNS rebinding at the transport layer.
nonisolated public enum PrivateHostPolicy {
    /// Returns whether `host` is local, private, link-local, multicast, or reserved.
    public static func isPrivateLocalhost(host: String) -> Bool {
        let bare = normalizedHost(host)

        if bare == "localhost" || bare.hasSuffix(".localhost") { return true }
        if bare == "local" || bare.hasSuffix(".local") { return true }

        let addressLiteral = bare.split(separator: "%", maxSplits: 1).first.map(String.init) ?? bare
        if let ipv6 = ipv6Bytes(from: addressLiteral) {
            if isLoopbackIPv6(ipv6) || isPrivateIPv6(ipv6) { return true }
            if isIPv4MappedIPv6(ipv6) {
                return isPrivateIPv4(Array(ipv6.suffix(4)))
            }
        }

        let ipv4 =
            addressLiteral.hasPrefix("::ffff:")
            ? String(addressLiteral.dropFirst("::ffff:".count)) : addressLiteral
        guard let octets = ipv4Octets(from: ipv4) else { return false }
        return isPrivateIPv4(octets)
    }

    /// Applies the default refusal policy, optionally permitting only this Mac's loopback interface.
    public static func isRefusedHost(_ host: String, allowLoopback: Bool) -> Bool {
        guard isPrivateLocalhost(host: host) else { return false }
        return !(allowLoopback && isLoopbackHost(host: host))
    }

    /// Returns whether `host` is strictly loopback, excluding LAN and multicast-DNS names.
    public static func isLoopbackHost(host: String) -> Bool {
        let bare = normalizedHost(host)
        if bare == "localhost" || bare.hasSuffix(".localhost") { return true }

        let addressLiteral = bare.split(separator: "%", maxSplits: 1).first.map(String.init) ?? bare
        if let ipv6 = ipv6Bytes(from: addressLiteral) {
            if isLoopbackIPv6(ipv6) { return true }
            if isIPv4MappedIPv6(ipv6) {
                return isLoopbackIPv4(Array(ipv6.suffix(4)))
            }
            return false
        }

        let ipv4 =
            addressLiteral.hasPrefix("::ffff:")
            ? String(addressLiteral.dropFirst("::ffff:".count)) : addressLiteral
        guard let octets = ipv4Octets(from: ipv4) else { return false }
        return isLoopbackIPv4(octets)
    }

    private static func normalizedHost(_ host: String) -> String {
        var bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        while bare.count > 1, bare.hasSuffix(".") { bare.removeLast() }
        return bare
    }

    private static func isLoopbackIPv4(_ octets: [UInt8]) -> Bool {
        octets.count == 4 && octets[0] == 127
    }

    /// Parses strict and legacy resolver-equivalent IPv4 literals without DNS.
    private static func ipv4Octets(from host: String) -> [UInt8]? {
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

    private static func ipv6Bytes(from host: String) -> [UInt8]? {
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

    private static func isLoopbackIPv6(_ bytes: [UInt8]) -> Bool {
        bytes.count == 16 && bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    }

    private static func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        if bytes[0] == 0xff { return true }
        if bytes[0] == 0xfe, (bytes[1] & 0xc0) >= 0x80 { return true }
        if (bytes[0] & 0xfe) == 0xfc { return true }
        return false
    }

    private static func isIPv4MappedIPv6(_ bytes: [UInt8]) -> Bool {
        bytes.count == 16
            && bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xff
            && bytes[11] == 0xff
    }

    private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        // RFC 6890 special-purpose space. Every range below is non-global: it is
        // either unroutable on the public Internet or routes to local/special-use
        // infrastructure, so a literal must never pass as a public origin. The
        // WebKit content rules in `PrivateNetworkBlockRules` encode the same set for
        // subresources; a parity test keeps the two in step.
        switch (octets[0], octets[1]) {
        case (0, _): return true  // "this" network
        case (10, _): return true  // private
        case (100, 64...127): return true  // shared address space (CGNAT)
        case (127, _): return true  // loopback
        case (169, 254): return true  // link-local
        case (172, 16...31): return true  // private
        case (192, 0): return octets[2] == 0 || octets[2] == 2  // IETF assignments, TEST-NET-1
        case (192, 88): return octets[2] == 99  // 6to4 relay anycast (deprecated, non-global)
        case (192, 168): return true  // private
        case (198, 18...19): return true  // benchmarking
        case (198, 51): return octets[2] == 100  // TEST-NET-2
        case (203, 0): return octets[2] == 113  // TEST-NET-3
        case (224...255, _): return true  // multicast, reserved, broadcast
        default: return false
        }
    }
}
