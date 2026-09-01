import Darwin
import Foundation

/// Records comparable steady-state footprint samples for opt-in memory journeys.
///
/// A sample is taken only after the journey has torn down its iteration and this probe
/// has given deferred AppKit/WebKit releases three bounded main-run-loop turns. Each
/// turn owns a fresh autorelease pool. The structured line is consumed by the local
/// memory-smoke harness; normal app launches never execute this code path.
enum MemoryJourneyProbe {
    enum ProbeError: Error, Equatable {
        case invalidIterationCount
        case footprintUnavailable(kern_return_t)
    }

    static let sampleMarker = "VITRINE_MEMORY_SAMPLE"
    static let maximumIterationCount = 100

    static func configuredIterationCount(
        default defaultCount: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Int {
        guard (1...maximumIterationCount).contains(defaultCount) else {
            throw ProbeError.invalidIterationCount
        }
        guard let rawValue = environment["VITRINE_MEMORY_ITERATIONS"] else {
            return defaultCount
        }
        guard let count = Int(rawValue), (1...maximumIterationCount).contains(count) else {
            throw ProbeError.invalidIterationCount
        }
        return count
    }

    static func record(journey: String, completedIteration: Int) async throws {
        try Task.checkCancellation()
        for _ in 0..<3 {
            autoreleasepool {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            await Task.yield()
        }
        try Task.checkCancellation()
        let footprint = try autoreleasepool { try physicalFootprintBytes() }
        let line =
            "\(sampleMarker) journey=\(journey) "
            + "iteration=\(completedIteration) physical-footprint-bytes=\(footprint)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    /// `TASK_VM_INFO.phys_footprint` is the process footprint used by Apple's memory
    /// tools. Sampling it directly avoids retaining Instruments objects in the process
    /// being measured and keeps the journey usable on clean release-QA Macs.
    static func physicalFootprintBytes() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count)
            }
        }
        guard status == KERN_SUCCESS else {
            throw ProbeError.footprintUnavailable(status)
        }
        return info.phys_footprint
    }
}
