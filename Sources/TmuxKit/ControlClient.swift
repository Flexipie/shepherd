import Foundation

/// The lines of tmux's control mode that Shepherd reacts to. Everything else is `other`.
public enum ControlEvent: Sendable, Equatable {
    /// A pane printed something, so its screen may have changed.
    case output(pane: String)
    /// Windows, sessions or layouts changed, so the set of panes may have changed.
    case layout
    /// A terminal left a session or moved to another, so which sessions are watched may have changed.
    case clients
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
        case "%client-detached", "%client-session-changed":
            return .clients
        case let word where layoutEvents.contains(String(word)):
            return .layout
        default:
            return .other
        }
    }
}

/// A control-mode client on one session of a server: `tmux -C attach-session`, so tmux pushes
/// output and layout events to Shepherd rather than Shepherd asking. tmux sends output only for
/// panes in the session a client is attached to, so following a whole server takes one client per
/// session. The client ignores window size, so attaching never resizes the user's windows. Its
/// output is read by a readability handler on the pipe's own queue, off the main actor: a read on
/// `FileHandle.bytes` waited behind the other clients' reads, so a quiet session held up the rest.
public actor ControlClient {
    private let binary: String
    private let socket: String
    private let session: String?
    private var process: Process?
    private var input: FileHandle?
    /// Set by `stop`, so a `start` that arrives after it does not attach.
    private var stopped = false

    /// `session` is a session id such as `$1`, which a rename does not change. Nil attaches to the
    /// session tmux picks, the most recently used.
    public init(binary: String, socket: String, session: String? = nil) {
        self.binary = binary
        self.socket = socket
        self.session = session
    }

    /// Attaches and starts reading. `events` gets each line's event in order. `ended` runs once when
    /// the client goes away, whether it was stopped or tmux detached it. Does nothing once stopped.
    public func start(events: @escaping @Sendable (ControlEvent) -> Void, ended: @escaping @Sendable () -> Void) throws {
        guard process == nil, !stopped else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-S", socket, "-C", "attach-session"] + (session.map { ["-t", $0] } ?? [])
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
        let lines = ControlLines()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            // End of the pipe: tmux exited, whether stopped or detached.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                ended()
                return
            }
            for line in lines.append(data) { events(ControlEvent.parse(line)) }
        }
    }

    /// Detaches: closing the input lets tmux exit cleanly, and the process is terminated if it has not.
    public func stop() {
        stopped = true
        try? input?.close()
        input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}

/// Splits the control client's output into lines. Only touched on the output handle's own serial
/// queue, hence the unchecked conformance.
private final class ControlLines: @unchecked Sendable {
    private var pending = Data()

    /// The complete lines `data` finishes; a partial line waits for the rest.
    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...end)
        }
        return lines
    }
}
