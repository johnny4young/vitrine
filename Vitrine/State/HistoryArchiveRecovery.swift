import Foundation

/// Reads usable entries without rewriting a damaged archive. The caller must retain
/// the original bytes and thumbnails until the user chooses recovery or deletion.
enum HistoryArchiveRecovery {
    struct Result {
        let captures: [Capture]
        let needsRecovery: Bool
    }

    static func decode(_ data: Data) -> Result {
        if let captures = try? JSONDecoder().decode([Capture].self, from: data),
            Set(captures.map(\.id)).count == captures.count
        {
            return Result(captures: captures, needsRecovery: false)
        }
        let entries: [Data]
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            entries = array.compactMap {
                try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed])
            }
        } else {
            entries = completeObjectEntries(in: data)
        }
        var seen = Set<UUID>()
        let captures = entries.compactMap { entry -> Capture? in
            guard let capture = try? JSONDecoder().decode(Capture.self, from: entry),
                seen.insert(capture.id).inserted
            else { return nil }
            return capture
        }
        return Result(captures: captures, needsRecovery: true)
    }

    /// Salvages complete top-level objects from a truncated JSON array, respecting
    /// nested containers, quoted braces and escaped quotes. No inner object is ever
    /// promoted to an entry. Invalid slices are still rejected by JSONDecoder.
    private static func completeObjectEntries(in data: Data) -> [Data] {
        let bytes = Array(data)
        let whitespace: Set<UInt8> = [9, 10, 13, 32]
        guard let opening = bytes.firstIndex(where: { !whitespace.contains($0) }),
            bytes[opening] == 91
        else { return [] }
        var entries: [Data] = []
        var start: Int?
        var expectedClosers: [UInt8] = []
        var quoted = false
        var escaped = false
        for index in bytes.indices where index > opening {
            let byte = bytes[index]
            if quoted {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    quoted = false
                }
                continue
            }
            if start == nil {
                if whitespace.contains(byte) || byte == 44 { continue }
                if byte == 93 { return entries }
                start = index
            }
            if byte == 34 {
                quoted = true
            } else if byte == 123 || byte == 91 {
                expectedClosers.append(byte == 123 ? 125 : 93)
            } else if byte == 125 || byte == 93 {
                if let expected = expectedClosers.last {
                    // Once nesting is ambiguous, only earlier complete entries are
                    // candidates. The full original remains available for recovery.
                    guard byte == expected else { return entries }
                    expectedClosers.removeLast()
                } else if byte == 93 {
                    if let start { entries.append(Data(bytes[start..<index])) }
                    return entries
                } else {
                    return entries
                }
            } else if byte == 44, expectedClosers.isEmpty {
                if let start { entries.append(Data(bytes[start..<index])) }
                start = nil
            }
        }
        if expectedClosers.isEmpty, !quoted, let start {
            entries.append(Data(bytes[start...]))
        }
        return entries
    }
}
