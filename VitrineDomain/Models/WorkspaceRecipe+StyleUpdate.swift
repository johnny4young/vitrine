import Foundation

extension StyleSnapshot {
    /// The encoded field names whose values differ from `baseline`, compared as the
    /// recipe file stores them, so a field added later is counted without listing it here.
    public func changedFields(from baseline: StyleSnapshot) -> Set<String> {
        let mine = Self.encodedFields(of: self)
        let theirs = Self.encodedFields(of: baseline)
        return Set(mine.keys).union(theirs.keys).filter { mine[$0] != theirs[$0] }
    }

    static func encodedFields(of style: StyleSnapshot) -> [String: NSObject] {
        guard let data = try? JSONEncoder().encode(style),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: NSObject]
        else { return [:] }
        return object
    }
}

extension WorkspaceRecipeDocument {
    /// Rewrites only `fields` of the recipe's style in `data`, keeping every other key and
    /// value as found. The result must pass the import contract, or nothing is returned.
    public static func updatingStyle(
        in data: Data, to style: StyleSnapshot, fields: Set<String>,
        customTheme: StoredCustomTheme?
    ) throws -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["format"] as? String == formatMarker,
            var recipe = root["recipe"] as? [String: Any]
        else { throw ImportError.notARecipeFile }
        var styleObject = recipe["style"] as? [String: Any] ?? [:]
        let encoded = StyleSnapshot.encodedFields(of: style)
        for field in fields { styleObject[field] = encoded[field] }
        recipe["style"] = styleObject
        if fields.contains("themeID") {
            recipe["customTheme"] = try customTheme.map {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
            }
        }
        root["recipe"] = recipe
        let output = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        _ = try Self.recipe(from: output)
        return output
    }
}
