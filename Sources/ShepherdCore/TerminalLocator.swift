import Darwin

/// Finds the app hosting a process, such as the terminal an agent runs in, by walking up the
/// process's ancestors. Knows nothing about any source: each source says which pids to start from.
public enum TerminalLocator {
    /// The hosting apps of `pids`, walking the live process table. `isApp` says whether a pid is an
    /// app the user sees (the sources check `NSRunningApplication`; Core has no AppKit).
    public static func hostingApps(of pids: [pid_t], isApp: (pid_t) -> Bool) -> [pid_t] {
        hostingApps(of: pids, parent: parent(of:), isApp: isApp)
    }

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

    /// The parent pid, or nil if the process is gone. Uses the short BSD info: the full one is
    /// refused for another user's process, and terminals start the shell through `login`, which
    /// runs as root, so a walk from an agent up to its terminal would stop there.
    public static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }
}
