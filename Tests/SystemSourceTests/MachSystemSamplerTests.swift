import Testing
@testable import ShepherdCore
@testable import SystemSource

@Suite struct MachSystemSamplerTests {
    @Test func busyIsTheShareOfTicksNotIdle() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 10)
        let new = CPUTicks(user: 160, system: 70, idle: 900, nice: 20)
        // 60 + 20 + 10 busy of 190.
        #expect(MachSystemSampler.busy(from: old, to: new) == 90.0 / 190.0)
    }

    @Test func noTimePassedIsNoReading() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(MachSystemSampler.busy(from: ticks, to: ticks) == nil)
    }

    @Test func countersThatWrapStillGiveTheDelta() {
        let old = CPUTicks(user: .max - 9, system: 0, idle: .max - 29, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        // 20 busy, 40 idle.
        #expect(MachSystemSampler.busy(from: old, to: new) == 20.0 / 60.0)
    }

    @Test func memoryUsedIsAppPlusWiredPlusCompressed() {
        let pages = MemoryPages(internal: 1000, purgeable: 100, wired: 200, compressed: 50, pageSize: 16384)
        #expect(MachSystemSampler.memoryUsed(pages) == 1150 * 16384)
    }

    @Test func morePurgeableThanInternalCountsNoAppMemory() {
        let pages = MemoryPages(internal: 10, purgeable: 20, wired: 5, compressed: 0, pageSize: 4096)
        #expect(MachSystemSampler.memoryUsed(pages) == 5 * 4096)
    }

    @MainActor @Test func theFirstSampleHasNoCPUAndTheSecondHasSome() async throws {
        let sampler = MachSystemSampler()
        let first = sampler.sample()
        #expect(first.cpu == nil)
        #expect(first.memoryTotal > 0)
        #expect(first.memoryUsed > 0 && first.memoryUsed <= first.memoryTotal)
        try await Task.sleep(for: .milliseconds(200))
        let cpu = try #require(sampler.sample().cpu)
        #expect((0...1).contains(cpu))
    }
}
