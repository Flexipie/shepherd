import Darwin

/// Finds the terminal app that hosts herdr. The attached herdr client is a descendant of the
/// terminal (for example herdr, zsh, login, Ghostty), while the herdr server descends from
/// launchd, so walking up from every `herdr` process finds the terminal and skips the server.
public enum TerminalLocator {
    /// Walks each pid's ancestors and returns the first that `isApp` accepts, without duplicates.
    public static func hostingApps(of pids: [pid_t], parent: (pid_t) -> pid_t?, isApp: (pid_t) -> Bool,
                                   maxDepth: Int = 16) -> [pid_t] {
        var found: [pid_t] = []
        for pid in pids {
            var current = parent(pid)
            var depth = 0
            while let candidate = current, candidate > 1, depth < maxDepth {
                if isApp(candidate) {
                    if !found.contains(candidate) { found.append(candidate) }
                    break
                }
                current = parent(candidate)
                depth += 1
            }
        }
        return found
    }

    /// Pids of running processes named `name`.
    public static func pids(named name: String) -> [pid_t] {
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

    /// The parent pid, or nil if the process is gone.
    public static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
