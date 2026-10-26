import Foundation

/// One process from `ps`: its id, its parent's id and its command line.
public struct ProcessEntry: Sendable, Equatable {
    public let pid: pid_t
    public let parent: pid_t
    public let command: String

    public init(pid: pid_t, parent: pid_t, command: String) {
        self.pid = pid
        self.parent = parent
        self.command = command
    }
}

/// The machine's processes, for finding what runs under a pane. It is read with one `ps` call when
/// asked and never kept up to date.
public struct ProcessTable: Sendable {
    private let entries: [pid_t: ProcessEntry]
    private let children: [pid_t: [pid_t]]

    public init(_ processes: [ProcessEntry]) {
        entries = Dictionary(processes.map { ($0.pid, $0) }) { first, _ in first }
        children = Dictionary(grouping: processes, by: \.parent).mapValues { $0.map(\.pid) }
    }

    /// `ps -axo pid=,ppid=,command=`, read in full before it is parsed. Empty when `ps` cannot run.
    public static func snapshot() -> ProcessTable {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ProcessTable([])
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> ProcessTable {
        ProcessTable(text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { return nil }
            return ProcessEntry(pid: pid, parent: parent, command: String(fields[2]))
        })
    }

    /// The names of `pid` and its descendants, nearest first. A name is the basename of the command,
    /// without `.exe`; when the command is an interpreter (`node /x/codex`), it is the script's name.
    public func names(under pid: pid_t) -> [String] {
        var queue = [pid]
        var seen = Set<pid_t>()
        var names: [String] = []
        var next = 0
        while next < queue.count {
            let current = queue[next]
            next += 1
            guard seen.insert(current).inserted, let entry = entries[current] else { continue }
            names.append(Self.name(of: entry.command))
            queue += children[current] ?? []
        }
        return names
    }

    static let interpreters: Set<String> = ["node", "bun", "python", "python3", "sh", "bash", "zsh"]

    static func name(of command: String) -> String {
        let words = command.split(separator: " ")
        guard let first = words.first else { return "" }
        var name = base(first)
        // A flag after the interpreter (`zsh -l`) names nothing; a path after it (`node /x/codex`) does.
        if interpreters.contains(name), words.count > 1, !words[1].hasPrefix("-") { name = base(words[1]) }
        return name.hasSuffix(".exe") ? String(name.dropLast(4)) : name
    }

    private static func base(_ word: Substring) -> String {
        String(word.split(separator: "/").last ?? word)
    }
}
