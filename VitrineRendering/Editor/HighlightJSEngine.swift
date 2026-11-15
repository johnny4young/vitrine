import Foundation
import JavaScriptCore

/// The Highlight.js engine and stylesheets bundled in Highlightr's resource bundle,
/// loaded into one JavaScriptCore context shared by the built-in and custom theme paths.
final class HighlightJSEngine {
    let hljs: JSValue
    private let context: JSContext

    init?() {
        guard let context = JSContext(),
            let scriptURL = Self.resourceURL("highlight.min", withExtension: "js"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else { return nil }
        context.evaluateScript(script)
        guard let hljs = context.objectForKeyedSubscript("hljs"), !hljs.isUndefined else {
            return nil
        }
        self.context = context
        self.hljs = hljs
    }

    /// Tokenizes `code` into Highlight.js HTML with the arguments Highlightr passes, so
    /// built-in themes keep their token classification: the named grammar without
    /// ignoring illegal input, then auto-detection when that fails or no name is given.
    func html(for code: String, languageName: String?) -> String? {
        var result: JSValue?
        if let languageName {
            result = hljs.invokeMethod(
                "highlight",
                withArguments: [code, ["language": languageName, "ignoreIllegals": false]])
        }
        if result == nil || result?.isUndefined == true {
            result = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }
        guard let value = result?.objectForKeyedSubscript("value"), !value.isUndefined else {
            return nil
        }
        return value.toString()
    }

    func supportedLanguages() -> [String] {
        hljs.invokeMethod("listLanguages", withArguments: [])?.toArray() as? [String] ?? []
    }

    /// The bundled stylesheet names, without the `.min.css` suffix.
    static func stylesheetNames() -> [String]? {
        guard let bundle = resourceBundle else { return nil }
        return bundle.paths(forResourcesOfType: "css", inDirectory: nil).map {
            ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".min.css", with: "")
        }
    }

    static func stylesheet(named name: String) -> String? {
        guard let url = resourceURL(name + ".min", withExtension: "css") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func resourceURL(_ name: String, withExtension ext: String) -> URL? {
        resourceBundle?.url(forResource: name, withExtension: ext)
    }

    /// Searches where SwiftPM's own accessor looks for Highlightr's resource bundle: the
    /// app's Resources, the bundle linking this code (a test bundle), and beside a CLI.
    private static let resourceBundle: Bundle? = {
        let candidates = [
            Bundle.main.resourceURL, Bundle(for: HighlightJSEngine.self).resourceURL,
            Bundle.main.bundleURL,
        ]
        for case let directory? in candidates {
            for name in ["Highlightr_Highlightr", "Highlightr"] {
                let url = directory.appending(path: name + ".bundle")
                if let bundle = Bundle(url: url),
                    bundle.url(forResource: "highlight.min", withExtension: "js") != nil
                {
                    return bundle
                }
            }
        }
        return nil
    }()
}
