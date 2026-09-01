import Testing

@testable import Vitrine

@MainActor
@Suite("Memory journey probe")
struct MemoryJourneyProbeTests {
    @Test func validatesBoundedIterationOverrides() throws {
        #expect(
            try MemoryJourneyProbe.configuredIterationCount(
                default: 20, environment: [:]) == 20)
        #expect(
            try MemoryJourneyProbe.configuredIterationCount(
                default: 20, environment: ["VITRINE_MEMORY_ITERATIONS": "100"]) == 100)

        for invalidDefault in [0, 101] {
            #expect(throws: MemoryJourneyProbe.ProbeError.invalidIterationCount) {
                try MemoryJourneyProbe.configuredIterationCount(
                    default: invalidDefault, environment: [:])
            }
        }

        for value in ["", "0", "101", "nope"] {
            #expect(throws: MemoryJourneyProbe.ProbeError.invalidIterationCount) {
                try MemoryJourneyProbe.configuredIterationCount(
                    default: 20, environment: ["VITRINE_MEMORY_ITERATIONS": value])
            }
        }
    }

    @Test func readsCurrentPhysicalFootprint() throws {
        #expect(try MemoryJourneyProbe.physicalFootprintBytes() > 0)
    }
}
