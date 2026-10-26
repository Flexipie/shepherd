import Darwin

/// Finds herdr's processes, to locate the terminal hosting herdr. The attached herdr client is a
/// descendant of the terminal (for example herdr, zsh, login, Ghostty), while the herdr server
/// descends from launchd, so walking up from every `herdr` process finds the terminal and skips the
/// server.
enum HerdrProcesses {
    /// Pids of running processes named `name`.
    static func pids(named name: String) -> [pid_t] {
        let capacity = proc_listallpids(nil, 0) + 64
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = proc_listallpids(&pids, capacity * Int32(MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: 256)
        return pids.prefix(Int(count)).filter { pid in
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            guard pid > 0, length > 0 else { return false }
            return String(decoding: buffer.prefix(Int(length)), as: UTF8.self) == name
        }
    }
}
