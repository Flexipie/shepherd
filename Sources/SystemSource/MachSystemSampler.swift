import Darwin
import Foundation
import ShepherdCore

/// Samples the whole Mac with Mach host calls: CPU from the kernel's tick counters, memory from
/// its VM statistics. Each call costs two system calls and reads no files. CPU is the busy share
/// of the ticks since the previous call, so the first call has none.
@MainActor
public final class MachSystemSampler: SystemSampler {
    private var previous: CPUTicks?
    private let memoryTotal = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func sample() -> SystemSample {
        let ticks = Self.cpuTicks()
        let cpu = zip(previous, ticks).flatMap { Self.busy(from: $0, to: $1) }
        previous = ticks ?? previous
        return SystemSample(cpu: cpu, memoryUsed: Self.memoryPages().map { Self.memoryUsed($0) } ?? 0,
                            memoryTotal: memoryTotal)
    }

    /// The share of the ticks between two readings spent busy (user, system or nice); nil when
    /// no time passed. The kernel's counters are 32 bit and wrap, so the deltas wrap too.
    nonisolated static func busy(from old: CPUTicks, to new: CPUTicks) -> Double? {
        let user = UInt64(new.user &- old.user)
        let system = UInt64(new.system &- old.system)
        let nice = UInt64(new.nice &- old.nice)
        let idle = UInt64(new.idle &- old.idle)
        let busy = user + system + nice
        let total = busy + idle
        return total == 0 ? nil : Double(busy) / Double(total)
    }

    /// Activity Monitor's "Memory Used": app memory (anonymous pages less purgeable ones), plus
    /// wired, plus compressed.
    nonisolated static func memoryUsed(_ pages: MemoryPages) -> UInt64 {
        let app = pages.internal > pages.purgeable ? pages.internal - pages.purgeable : 0
        return (app + pages.wired + pages.compressed) * pages.pageSize
    }

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private static func memoryPages() -> MemoryPages? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        return MemoryPages(internal: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                           wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                           pageSize: UInt64(pageSize))
    }
}

/// The kernel's cumulative CPU ticks, summed over every core.
struct CPUTicks: Sendable, Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// The VM page counts behind "Memory Used".
struct MemoryPages: Sendable, Equatable {
    var `internal`: UInt64
    var purgeable: UInt64
    var wired: UInt64
    var compressed: UInt64
    var pageSize: UInt64
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
