import AppKit

/// Marks app-authored exports as confidential for cooperating clipboard managers.
/// This is a convention, not access control; it never replaces content sanitization.
public enum ClipboardWriter {
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Objects without a writable type are skipped, so an empty write never clears the
    /// existing clipboard.
    @discardableResult
    public static func write(
        _ objects: [NSPasteboardWriting], concealed: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let writable = objects.filter { !$0.writableTypes(for: pasteboard).isEmpty }
        let output: [NSPasteboardWriting] =
            concealed ? writable.compactMap { concealedItem(for: $0, on: pasteboard) } : writable
        guard !output.isEmpty, output.count == writable.count else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(output)
    }

    /// Materializes every representation `object` can provide for `pasteboard` onto a
    /// fresh item. Types that yield no value are skipped.
    public static func item(
        from object: NSPasteboardWriting, for pasteboard: NSPasteboard
    ) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for type in object.writableTypes(for: pasteboard) {
            // Data representations are already encoded. Property-list encoding them
            // again would corrupt PNG/RTF and turn strings into binary plists.
            switch object.pasteboardPropertyList(forType: type) {
            case let data as Data: item.setData(data, forType: type)
            case let text as String: item.setString(text, forType: type)
            case let value?: item.setPropertyList(value, forType: type)
            case nil: break
            }
        }
        return item
    }

    private static func concealedItem(
        for object: NSPasteboardWriting, on pasteboard: NSPasteboard
    ) -> NSPasteboardItem? {
        let item = item(from: object, for: pasteboard)
        guard !item.types.isEmpty, item.setData(Data(), forType: concealedType) else {
            return nil
        }
        return item
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
