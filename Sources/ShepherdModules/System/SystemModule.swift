import Foundation
import Observation
import ShepherdCore

/// The whole Mac's CPU and memory, as a panel section with one meter card. It samples only while
/// a panel is open: once on opening, then every `interval`. Closed, nothing runs. With no sampler
/// in the context it has no section.
@MainActor
@Observable
public final class SystemModule: ShepherdModule {
    public static let id = "system"

    private(set) var sample: SystemSample?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var sampling: Task<Void, Never>?
    /// The sampler's CPU share covers the time since its last sample, which after a close is
    /// the whole closed spell. So the first sample of an opening only primes it, and the next
    /// comes sooner than the rest.
    @ObservationIgnored var firstInterval: TimeInterval = 0.5
    @ObservationIgnored var interval: TimeInterval = 2

    public init(context: ModuleContext) {
        self.context = context
        watchVisibility()
    }

    public var panel: PanelSection? {
        guard context.system != nil else { return nil }
        let items = sample.map { [PanelItem.usage(Self.provider($0))] } ?? []
        return PanelSection(id: Self.id, title: "This Mac", items: items, emptyText: "Measuring…")
    }

    private func watchVisibility() {
        let visible = withObservationTracking {
            context.presence.isPanelVisible
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchVisibility() }
        }
        guard visible != isVisible else { return }
        isVisible = visible
        sampling?.cancel()
        sampling = nil
        guard visible, let sampler = context.system else { return }
        let primed = sampler.sample()
        sample = SystemSample(cpu: nil, memoryUsed: primed.memoryUsed, memoryTotal: primed.memoryTotal)
        sampling = Task { @MainActor [weak self, firstInterval, interval] in
            var delay = firstInterval
            while true {
                try? await Task.sleep(for: .seconds(delay))
                // Presence, not `isVisible`: a close may not have reached `watchVisibility` yet.
                guard !Task.isCancelled, let self, self.context.presence.isPanelVisible else { return }
                self.sample = sampler.sample()
                delay = interval
            }
        }
    }

    /// The sample as a meter card: "CPU 23%", "Memory 18.2 of 36 GB".
    static func provider(_ sample: SystemSample) -> UsageProvider {
        let cpu = UsageMeter(id: "cpu", label: "CPU", fraction: sample.cpu ?? 0,
                             valueText: sample.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
        let total = sample.memoryTotal
        let memory = UsageMeter(id: "memory", label: "Memory", fraction: total == 0 ? 0 : Double(sample.memoryUsed) / Double(total),
                                valueText: "\(gigabytes(sample.memoryUsed, decimals: 1)) of \(gigabytes(total, decimals: 0)) GB")
        return UsageProvider(id: id, name: "CPU and memory", meters: [cpu, memory])
    }

    /// Binary gigabytes, as Activity Monitor counts them.
    static func gigabytes(_ bytes: UInt64, decimals: Int) -> String {
        String(format: "%.\(decimals)f", Double(bytes) / 1_073_741_824)
    }
}
