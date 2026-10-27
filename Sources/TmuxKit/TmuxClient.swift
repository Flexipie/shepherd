import Darwin
import Foundation

/// A pane as `tmux list-panes -a` reports it. `paneID` is tmux's own id, such as `%3`, unique within
/// one server; `socket` says which server it is on.
public struct TmuxPane: Sendable, Equatable {
    public let socket: String
    public let session: String
    /// Such as `@2`.
    public let windowID: String
    public let windowIndex: Int
    /// Such as `%3`.
    public let paneID: String
    /// The pane's process: its shell, or the command it runs directly.
    public let pid: pid_t
    /// Its window is the session's current one and the pane is the window's active pane.
    public let isActive: Bool
    /// The command tmux thinks runs in the pane. Not what an agent is called: Claude Code shows as
    /// `claude.exe`, so the process table is the match.
    public let command: String
    public let path: String

    /// One tab-separated line per pane. The path comes last, since it is the only field that may hold a tab.
    static let format = ["#{session_name}", "#{window_id}", "#{window_index}", "#{pane_id}", "#{pane_pid}",
                         "#{window_active}", "#{pane_active}", "#{pane_current_command}", "#{pane_current_path}"]
        .joined(separator: "\t")

    public static func parse(_ line: String, socket: String) -> TmuxPane? {
        let fields = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false)
        guard fields.count == 9, let index = Int(fields[2]), let pid = Int32(fields[4]) else { return nil }
        return TmuxPane(socket: socket, session: String(fields[0]), windowID: String(fields[1]), windowIndex: index,
                        paneID: String(fields[3]), pid: pid, isActive: fields[5] == "1" && fields[6] == "1",
                        command: String(fields[7]), path: String(fields[8]))
    }
}

/// A session as `tmux list-sessions` reports it.
public struct TmuxSession: Sendable, Equatable {
    /// Such as `$1`; a rename does not change it.
    public let id: String
    public let name: String
    /// When it was last used, in whole seconds.
    public let activity: Int
    /// tmux closes it once no client is attached (`destroy-unattached`), so a control client left on
    /// it would keep it open.
    public let closesWhenUnattached: Bool

    /// One tab-separated line per session. The name comes last, since it may hold a tab.
    static let format = ["#{session_activity}", "#{destroy-unattached}", "#{session_grouped}", "#{session_group_size}",
                         "#{session_id}", "#{session_name}"].joined(separator: "\t")

    public static func parse(_ line: String) -> TmuxSession? {
        let fields = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
        guard fields.count == 6, let activity = Int(fields[0]) else { return nil }
        let grouped = fields[2] == "1"
        let groupSize = Int(fields[3]) ?? 0
        // tmux's values: off and on, and since 3.4 keep-last (closes only with others in its group)
        // and keep-group (closes unless it is the only one in its group). Anything else, empty
        // included, is read as closing, the side that never keeps a session open.
        let closes = switch fields[1] {
        case "off": false
        case "keep-last": grouped && groupSize > 1
        case "keep-group": !(grouped && groupSize == 1)
        default: true
        }
        return TmuxSession(id: String(fields[4]), name: String(fields[5]), activity: activity, closesWhenUnattached: closes)
    }
}

/// A client attached to a server: a terminal's `tmux` process, or Shepherd's own control client.
public struct TmuxAttachedClient: Sendable, Equatable {
    public let pid: pid_t
    public let session: String
    /// Shepherd's own control-mode clients. Not a terminal, so nothing shows them.
    public let isControl: Bool

    public static let format = ["#{client_pid}", "#{client_session}", "#{client_control_mode}"].joined(separator: "\t")

    public static func parse(_ line: String) -> TmuxAttachedClient? {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, let pid = Int32(fields[0]) else { return nil }
        return TmuxAttachedClient(pid: pid, session: String(fields[1]), isControl: fields[2] == "1")
    }
}

/// Why a tmux command failed, in words a person can read.
public enum TmuxError: Error, Equatable, CustomStringConvertible {
    /// No server answers on the socket: none is running, or the socket is stale.
    case noServer
    case failed(String)

    public var description: String {
        switch self {
        case .noServer: "no tmux server is running"
        case .failed(let message): "tmux: \(message)"
        }
    }
}

/// Runs `tmux` against one server, by its socket path, with `-S`. Every call blocks until tmux
/// exits, so call it off the main actor.
public struct TmuxClient: Sendable {
    public let binary: String
    public let socket: String

    public init(binary: String, socket: String) {
        self.binary = binary
        self.socket = socket
    }

    /// The `tmux` binary: the first on `PATH`, else where Homebrew and the system put it (an app
    /// launched from Finder has a short `PATH`). Nil when tmux is not installed.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in path + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        where FileManager.default.isExecutableFile(atPath: directory + "/tmux") {
            return directory + "/tmux"
        }
        return nil
    }

    /// Every pane on the server, in tmux's order.
    public func panes() throws -> [TmuxPane] {
        try run(["list-panes", "-a", "-F", TmuxPane.format]).split(separator: "\n").compactMap {
            TmuxPane.parse(String($0), socket: socket)
        }
    }

    /// Every session, least recently used first. A session a client attaches to becomes the most
    /// recently used, which is where a plain `tmux attach` goes, so attaching in this order keeps
    /// the user's latest session the latest.
    public func sessions() throws -> [TmuxSession] {
        try run(["list-sessions", "-F", TmuxSession.format]).split(separator: "\n")
            .compactMap { TmuxSession.parse(String($0)) }
            .sorted { $0.activity < $1.activity }
    }

    public func clients() throws -> [TmuxAttachedClient] {
        try run(["list-clients", "-F", TmuxAttachedClient.format]).split(separator: "\n").compactMap {
            TmuxAttachedClient.parse(String($0))
        }
    }

    /// The pane's visible lines, as plain text.
    public func screen(_ pane: String) throws -> String {
        try run(["capture-pane", "-p", "-t", pane])
    }

    /// The pane's last `lines` lines, scrollback included.
    public func history(_ pane: String, lines: Int) throws -> String {
        try run(["capture-pane", "-p", "-t", pane, "-S", "-\(lines)"])
    }

    public func selectWindow(_ window: String) throws {
        _ = try run(["select-window", "-t", window])
    }

    public func selectPane(_ pane: String) throws {
        _ = try run(["select-pane", "-t", pane])
    }

    /// Opens a window in `folder` running `command` (its program and arguments, with no shell
    /// between them), placed after `window` in its session, without switching to it. Returns the
    /// new pane's id, such as `%7`. tmux gives the pane the PATH of the `tmux` process that asked
    /// for it (`-e` cannot change that), so `path`, when given, is that process's PATH.
    public func newWindow(after window: String, folder: String, name: String, path: String? = nil,
                          command: [String]) throws -> String {
        // The name is a format: `##` keeps a `#` in a branch name from expanding.
        try run(["new-window", "-d", "-a", "-t", window, "-c", folder, "-n", name.replacingOccurrences(of: "#", with: "##"),
                 "-P", "-F", "#{pane_id}"] + command,
                path: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A variable in the server's global environment: what it was started with, from the user's
    /// terminal. Nil when it is not set.
    public func globalEnvironment(_ name: String) -> String? {
        let line = (try? run(["show-environment", "-g", name]))?.trimmingCharacters(in: .newlines) ?? ""
        return line.hasPrefix(name + "=") ? String(line.dropFirst(name.count + 1)) : nil
    }

    /// Types `text` into the pane as literal characters, so a `-` or a `;` in it is not a flag.
    public func sendLiteral(_ pane: String, _ text: String) throws {
        _ = try run(["send-keys", "-t", pane, "-l", "--", text])
    }

    /// Presses named keys in the pane, such as `Enter`. `keys` are in surface names: see `TmuxKeys`.
    public func sendKeys(_ pane: String, _ keys: [String]) throws {
        _ = try run(["send-keys", "-t", pane] + keys.map(TmuxKeys.name))
    }

    /// Runs one command and returns its standard output. A failure says what tmux said.
    func run(_ arguments: [String], path: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Shepherd may itself run inside tmux; the commands must talk to `socket`, not that server.
        environment["TMUX"] = nil
        environment["TMUX_PANE"] = nil
        if let path { environment["PATH"] = path }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Read everything before waiting: a full pipe would otherwise stop tmux and never exit.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if message.contains("no server running") || message.contains("error connecting") { throw TmuxError.noServer }
            throw TmuxError.failed(message.isEmpty ? "exited with \(process.terminationStatus)" : message)
        }
        return String(decoding: output, as: UTF8.self)
    }
}

/// Surface key names mapped to tmux's. Anything else is passed through, so tmux's own names work too.
public enum TmuxKeys {
    public static func name(_ key: String) -> String {
        switch key.lowercased() {
        case "enter", "return": "Enter"
        case "escape", "esc": "Escape"
        case "tab": "Tab"
        case "backspace": "BSpace"
        case "space": "Space"
        case "up", "down", "left", "right": key.capitalized
        default: key
        }
    }
}

/// Where tmux keeps its server sockets: `$TMUX_TMPDIR` (else `/tmp`), in a folder named for the
/// user's id.
public enum TmuxSockets {
    public static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["TMUX_TMPDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp"
        return URL(fileURLWithPath: base).appending(path: "tmux-\(getuid())")
    }

    /// The socket files in `directory`, by full path, sorted. A missing folder has none. Paths are
    /// real ones (`/private/tmp`, not `/tmp`), as tmux's own `#{socket_path}` and `$TMUX` give them,
    /// so a report from inside a pane names the same socket.
    public static func sockets(in directory: URL) -> [String] {
        let real = realpath(directory.path, nil).map { pointer in
            defer { free(pointer) }
            return URL(fileURLWithPath: String(cString: pointer))
        } ?? directory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: real.path)) ?? []
        return names.sorted().map { real.appending(path: $0).path }.filter { path in
            (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSocket
        }
    }
}
