import Foundation

/// The lines of tmux's control mode that Shepherd reacts to. Everything else is `other`.
public enum ControlEvent: Sendable, Equatable {
    /// A pane printed something, so its screen may have changed.
    case output(pane: String)
    /// Windows, sessions or layouts changed, so the set of panes may have changed.
    case layout
    /// The client was detached, usually because its server exited.
    case exit
    case other

    /// Events that change which panes exist or where they are.
    static let layoutEvents: Set<String> = [
        "%window-add", "%window-close", "%window-renamed", "%window-pane-changed",
        "%unlinked-window-add", "%unlinked-window-close", "%unlinked-window-renamed",
        "%session-changed", "%session-renamed", "%session-window-changed", "%sessions-changed",
        "%layout-change",
    ]

    public static func parse(_ line: String) -> ControlEvent {
        guard line.hasPrefix("%") else { return .other }
        let words = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        switch words[0] {
        case "%output", "%extended-output":
            guard words.count > 1 else { return .other }
            return .output(pane: String(words[1]))
        case "%exit":
            return .exit
        case let word where layoutEvents.contains(String(word)):
            return .layout
        default:
            return .other
        }
    }
}

/// A control-mode client on one server: `tmux -C attach-session`, so tmux pushes output and layout
/// events to Shepherd rather than Shepherd asking. The client ignores window size, so attaching
/// never resizes the user's windows. Its reader runs on this actor's own task, off the main actor.
public actor ControlClient {
    private let binary: String
    private let socket: String
    private var process: Process?
    private var input: FileHandle?
    private var reader: Task<Void, Never>?

    public init(binary: String, socket: String) {
        self.binary = binary
        self.socket = socket
    }

    /// Attaches and starts reading. `events` gets each line's event in order. `ended` runs once when
    /// the client goes away, whether it was stopped or tmux detached it.
    public func start(events: @escaping @Sendable (ControlEvent) -> Void, ended: @escaping @Sendable () -> Void) throws {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket, "-C", "attach-session"]
        var environment = ProcessInfo.processInfo.environment
        environment["TMUX"] = nil
        environment["TMUX_PANE"] = nil
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        // A command on the control client's input. The flag keeps the client from resizing windows.
        try? input?.write(contentsOf: Data("refresh-client -f ignore-size\n".utf8))
        let output = stdout.fileHandleForReading
        reader = Task {
            do {
                for try await line in output.bytes.lines {
                    events(ControlEvent.parse(line))
                }
            } catch {
                // A read that fails ends the client the same way a closed pipe does.
            }
            ended()
        }
    }

    /// Detaches: closing the input lets tmux exit cleanly, and the process is terminated if it has not.
    public func stop() {
        reader?.cancel()
        reader = nil
        try? input?.close()
        input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}
