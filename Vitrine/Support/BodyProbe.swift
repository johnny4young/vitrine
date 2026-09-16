import Foundation

// Measurement-only probe for the style-facade gate. Never committed.
enum BodyProbe {
    static var counts: [String: Int] = [:]
    static var nanos: [String: UInt64] = [:]
    private static var starts: [String: UInt64] = [:]

    static func begin(_ name: String) -> Int {
        counts[name, default: 0] += 1
        starts[name] = DispatchTime.now().uptimeNanoseconds
        return 0
    }

    static func end(_ name: String) -> Int {
        if let start = starts[name] {
            nanos[name, default: 0] += DispatchTime.now().uptimeNanoseconds - start
        }
        return 0
    }

    static func reset() {
        counts = [:]
        nanos = [:]
        starts = [:]
    }
}
