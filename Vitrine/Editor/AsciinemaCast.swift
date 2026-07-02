import Foundation

/// Parses asciinema recordings (`.cast`) into replayable terminal text.
///
/// An asciinema v2/v3 cast is JSON-lines: a header object (`{"version": 2, …}`)
/// followed by one event per line — `[time, type, data]` — where type `"o"` carries
/// the exact bytes the recorded session wrote to the terminal. Concatenating the
/// `"o"` payloads reproduces the session's final byte stream, which the existing
/// ANSI/terminal pipeline already knows how to render, so importing a recording
/// costs no new rendering code.
///
/// Pure and Foundation-only (no AppKit, no filesystem), so it is fully
/// unit-testable and compiles in the headless CLI target unchanged. Malformed
/// input returns `nil` rather than throwing: a `.cast`-named file that is not a
/// real recording falls back to the ordinary text-load path instead of erroring.
enum AsciinemaCast {
    /// Whether `filename` looks like an asciinema recording (a `.cast` extension,
    /// case-insensitive). Cheap filename gate so the JSONL parse only runs on
    /// files that claim to be recordings.
    static func isCastFilename(_ filename: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == "cast"
    }

    /// Replays the recording in `text` to the terminal bytes it produced, or `nil`
    /// when `text` is not a valid v2/v3 cast (wrong header, not JSON-lines).
    ///
    /// Only `"o"` (output) events contribute bytes; input echoes (`"i"`), resizes
    /// (`"r"`), and markers (`"m"`) are timing/metadata and are skipped. A
    /// malformed *event* line is skipped rather than failing the whole file —
    /// recordings are occasionally truncated mid-write — but a malformed *header*
    /// rejects the file, so ordinary JSON never masquerades as a recording.
    static func terminalText(from text: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)[...]

        guard let headerLine = lines.first,
            let headerData = String(headerLine).data(using: .utf8),
            let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
            let version = header["version"] as? Int,
            version == 2 || version == 3
        else { return nil }
        lines = lines.dropFirst()

        var output = ""
        for line in lines {
            guard let data = String(line).data(using: .utf8),
                let event = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
                event.count >= 3,
                let type = event[1] as? String,
                let payload = event[2] as? String
            else { continue }
            if type == "o" { output.append(payload) }
        }
        return output
    }
}
