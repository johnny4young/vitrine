import AppKit

/// Marks app-authored exports as confidential for cooperating clipboard managers.
/// This is a convention, not access control; it never replaces content sanitization.
public enum ClipboardWriter {
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @discardableResult
    public static func write(
        _ objects: [NSPasteboardWriting], concealed: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let output: [NSPasteboardWriting]
        if concealed {
            var items: [NSPasteboardItem] = []
            for object in objects {
                let item = NSPasteboardItem()
                for type in object.writableTypes(for: pasteboard) {
                    guard let value = object.pasteboardPropertyList(forType: type) else {
                        return false
                    }
                    // Data representations are already encoded. Property-list encoding
                    // them again would corrupt PNG/RTF and turn strings into binary plists.
                    let written: Bool
                    if let data = value as? Data {
                        written = item.setData(data, forType: type)
                    } else if let text = value as? String {
                        written = item.setString(text, forType: type)
                    } else {
                        written = item.setPropertyList(value, forType: type)
                    }
                    guard written else { return false }
                }
                guard !item.types.isEmpty,
                    item.setData(Data(), forType: concealedType)
                else { return false }
                items.append(item)
            }
            output = items
        } else {
            output = objects
        }
        guard !output.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(output)
    }

    @discardableResult
    public static func copy(
        _ text: String, concealed: Bool = false, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return false }
        return write([item], concealed: concealed, to: pasteboard)
    }

    @discardableResult
    public static func copy(
        _ data: Data, type: NSPasteboard.PasteboardType,
        concealed: Bool = false, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(data, forType: type) else { return false }
        return write([item], concealed: concealed, to: pasteboard)
    }
}
