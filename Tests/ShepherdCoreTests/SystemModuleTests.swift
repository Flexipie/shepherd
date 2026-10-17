import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class StubSystemSampler: SystemSampler {
    var samples = 0

    func sample() -> SystemSample {
        samples += 1
        return SystemSample(cpu: 0.25, memoryUsed: 19_541_180_416, memoryTotal: 38_654_705_664)
    }
}

@MainActor
@Suite struct SystemModuleTests {
    let presence = Presence()
    let sampler = StubSystemSampler()

    func module() -> SystemModule {
        let module = SystemModule(context: ModuleContext(store: HerdStore(), presence: presence, actions: RecordingActions(),
                                                         system: sampler))
        module.firstInterval = 0.02
        module.interval = 0.05
        return module
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func nothingIsSampledWhileHidden() async {
        let module = module()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(sampler.samples == 0)
        #expect(module.panel?.items == [])
        #expect(module.panel?.emptyText == "Measuring…")
    }

    @Test func switchingToAgentsStopsSampling() async {
        let module = module()
        presence.setPanel("menu", showing: .agents)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(sampler.samples == 0)
        #expect(module.panel?.tab == .gadgets)
        presence.setPanel("menu", showing: .gadgets)
        await until { sampler.samples >= 2 }
        presence.setPanel("menu", showing: .agents)
        try? await Task.sleep(for: .milliseconds(30))
        let after = sampler.samples
        try? await Task.sleep(for: .milliseconds(250))
        #expect(sampler.samples == after)
    }

    @Test func openingSamplesAndKeepsSampling() async {
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { sampler.samples >= 1 }
        // The first sample of an opening only primes the CPU reading.
        #expect(module.sample?.cpu == nil)
        await until { sampler.samples >= 3 }
        #expect(sampler.samples >= 3)
        #expect(module.sample?.cpu == 0.25)
    }

    @Test func closingStopsSampling() async {
        let module = module()
        presence.setPanel("notch", showing: .gadgets)
        await until { sampler.samples >= 2 }
        presence.setPanel("notch", showing: nil)
        try? await Task.sleep(for: .milliseconds(30))
        let after = sampler.samples
        try? await Task.sleep(for: .milliseconds(250))
        #expect(sampler.samples == after)
        _ = module
    }

    @Test func theSampleIsAMeterCard() {
        let provider = SystemModule.provider(SystemSample(cpu: 0.234, memoryUsed: 19_541_180_416, memoryTotal: 38_654_705_664))
        #expect(provider.meters.map(\.label) == ["CPU", "Memory"])
        #expect(provider.meters.map(\.valueText) == ["23%", "18.2 of 36 GB"])
        #expect(provider.meters[1].fraction == 19_541_180_416.0 / 38_654_705_664.0)
    }

    @Test func noCPUYetIsAnEllipsis() {
        let provider = SystemModule.provider(SystemSample(cpu: nil, memoryUsed: 0, memoryTotal: 0))
        #expect(provider.meters[0].valueText == "…")
        #expect(provider.meters[1].fraction == 0)
    }

    @Test func noSamplerNoSection() {
        let module = SystemModule(context: ModuleContext(store: HerdStore(), presence: presence, actions: RecordingActions()))
        #expect(module.panel == nil)
    }
}
