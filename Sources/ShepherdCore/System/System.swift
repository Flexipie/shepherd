/// The whole Mac's load at one moment, as a sampler measured it.
public struct SystemSample: Sendable, Equatable {
    /// The share of CPU time spent busy since the previous sample, 0...1; nil on the first.
    public let cpu: Double?
    /// Memory in use, in bytes, as Activity Monitor's "Memory Used".
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64

    public init(cpu: Double?, memoryUsed: UInt64, memoryTotal: UInt64) {
        self.cpu = cpu.map { min(max($0, 0), 1) }
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
    }
}

/// Measures the whole Mac once per call. The app's sampler lives in its own target, so modules
/// decide when to sample and never make the system calls themselves.
@MainActor
public protocol SystemSampler: AnyObject {
    func sample() -> SystemSample
}
