import Foundation

extension StyleSnapshot {
    /// The encoded field names whose values differ from `baseline`, compared as a preset or
    /// recipe file stores them, so a field added later is counted without listing it here.
    public func changedFields(from baseline: StyleSnapshot) -> Set<String> {
        let mine = Self.encodedFields(of: self)
        let theirs = Self.encodedFields(of: baseline)
        return Set(mine.keys).union(theirs.keys).filter { mine[$0] != theirs[$0] }
    }

    private static func encodedFields(of style: StyleSnapshot) -> [String: NSObject] {
        guard let data = try? JSONEncoder().encode(style),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: NSObject]
        else { return [:] }
        return object
    }
}
