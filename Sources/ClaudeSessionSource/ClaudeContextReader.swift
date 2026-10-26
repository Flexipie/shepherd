import Foundation
import ShepherdCore

/// Reads a Claude Code agent's context size and last message from its session file:
/// `<config>/projects/<cwd, every non-alphanumeric character as "-">/<session id>.jsonl`, where
/// `<config>` is `CLAUDE_CONFIG_DIR` or `~/.claude`. When that file is missing (the agent changed
/// directory), it looks for `<session id>.jsonl` in every project folder once and remembers it.
///
/// Read-only, and only the file's last `tailBytes`. The size is the last main-thread assistant
/// turn's input plus cache read plus cache creation tokens; the message is the text of the latest
/// turn's last main-thread assistant entry that has any. An unchanged file (same size and
/// modification date) costs one `stat`. Other agent kinds read nothing and give nil.
@MainActor
public final class ClaudeContextReader: AgentContextReader {
    public nonisolated static let tailBytes = 256 * 1024

    private let projects: URL
    private var paths: [String: URL] = [:]
    private var cache: [URL: ClaudeSessionFile.Reading] = [:]

    public init(configDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = configDirectory
            ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".claude")
        projects = directory.appending(path: "projects")
    }

    public func read(_ session: AgentSession) async throws -> AgentSessionReading? {
        guard session.kind == "claude", ClaudeSessionFile.isSafeID(session.id) else { return nil }
        let expected = session.cwd.map { projects.appending(path: ClaudeSessionFile.folderName($0)).appending(path: "\(session.id).jsonl") }
        let candidates = [paths[session.id], expected].compactMap { $0 }
        let result = try await ClaudeSessionFile.locateAndRead(id: session.id, candidates: candidates, projects: projects,
                                                               cache: cache, tailBytes: Self.tailBytes)
        paths[session.id] = result?.url
        guard let result else { return nil }
        cache[result.url] = result.reading
        return AgentSessionReading(contextTokens: result.reading.tokens, finalMessage: result.reading.finalMessage)
    }
}

/// The file work behind `ClaudeContextReader`, free of any actor so it runs off the main one.
enum ClaudeSessionFile {
    /// One read of a session file, kept so an unchanged file is not read again.
    struct Reading: Sendable, Equatable {
        let size: UInt64
        let modified: Date
        let tokens: Int?
        let finalMessage: String?

        init(size: UInt64, modified: Date, tokens: Int?, finalMessage: String? = nil) {
            self.size = size
            self.modified = modified
            self.tokens = tokens
            self.finalMessage = finalMessage
        }
    }

    /// Longer messages are cut here, so a surface never lays out a whole log.
    static let messageLimit = 10_000

    /// Claude Code's folder name for a working directory: every character that is not an ASCII
    /// letter or digit becomes "-".
    static func folderName(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : "-"
        })
    }

    /// A session id is only letters, digits, "-" and "_", so it can never leave the folder.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128
            && id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

    /// Finds the session's file and reads it, off the caller's actor.
    @concurrent
    static func locateAndRead(id: String, candidates: [URL], projects: URL, cache: [URL: Reading],
                              tailBytes: Int) async throws -> (url: URL, reading: Reading)? {
        guard let url = locate(id: id, candidates: candidates, projects: projects) else { return nil }
        return (url, try read(url, previous: cache[url], tailBytes: tailBytes))
    }

    /// The first candidate that exists, else a search of every project folder.
    static func locate(id: String, candidates: [URL], projects: URL) -> URL? {
        let manager = FileManager.default
        if let hit = candidates.first(where: { manager.fileExists(atPath: $0.path) }) { return hit }
        let folders = (try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.lazy.map { $0.appending(path: "\(id).jsonl") }.first { manager.fileExists(atPath: $0.path) }
    }

    static func read(_ url: URL, previous: Reading?, tailBytes: Int) throws -> Reading {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        if let previous, previous.size == size, previous.modified == modified { return previous }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        let turn = lastTurn(in: data, cutAtStart: offset > 0)
        return Reading(size: size, modified: modified, tokens: turn.tokens, finalMessage: turn.finalMessage)
    }

    static func lastContextTokens(in data: Data, cutAtStart: Bool) -> Int? {
        lastTurn(in: data, cutAtStart: cutAtStart).tokens
    }

    /// Walks the lines from the end over the main thread's entries (not a sidechain): the last
    /// assistant entry with usage (not a synthetic error) gives the context size, the last one
    /// with text the final message. The message is only looked for in the latest turn: a prompt,
    /// an interruption or an API error after it means there is none, so a surface shows the
    /// agent's lines instead of an earlier answer. `cutAtStart` drops the first line, which the
    /// tail window may have cut.
    static func lastTurn(in data: Data, cutAtStart: Bool) -> (tokens: Int?, finalMessage: String?) {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if cutAtStart, !lines.isEmpty { lines.removeFirst() }
        let markers = [Data(#""assistant""#.utf8), Data(#""user""#.utf8)]
        var tokens: Int?
        var finalMessage: String?
        var messageDone = false
        for line in lines.reversed() where markers.contains(where: { line.range(of: $0) != nil }) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "user":
                if !messageDone, object["isMeta"] as? Bool != true, !isToolResult(message), !isLocalCommand(message) {
                    messageDone = true
                }
            case "assistant":
                guard message["model"] as? String != "<synthetic>" else {
                    messageDone = true
                    continue
                }
                if tokens == nil, let usage = message["usage"] as? [String: Any] {
                    let keys = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    let total = keys.reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
                    if total > 0 { tokens = total }
                }
                if !messageDone, let text = text(of: message) {
                    finalMessage = text
                    messageDone = true
                }
            default: continue
            }
            if tokens != nil, messageDone { break }
        }
        return (tokens, finalMessage)
    }

    /// A user entry Claude Code writes for a local slash command (`/cost`, `/model`): its name
    /// and its output, in tags. It starts no turn, so the answer before it still stands. A skill or
    /// custom command starts with `<command-message>` instead and is a prompt.
    static func isLocalCommand(_ message: [String: Any]) -> Bool {
        let text = message["content"] as? String
            ?? (message["content"] as? [[String: Any]])?.first.flatMap { $0["text"] as? String } ?? ""
        let start = text.drop { $0.isWhitespace }
        return start.hasPrefix("<command-name>") || start.hasPrefix("<local-command-")
    }

    /// A user entry that only carries tool results, which Claude Code writes inside a turn.
    static func isToolResult(_ message: [String: Any]) -> Bool {
        guard let blocks = message["content"] as? [[String: Any]], !blocks.isEmpty else { return false }
        return blocks.allSatisfy { $0["type"] as? String == "tool_result" }
    }

    /// The message's text blocks joined, trimmed and cut at `messageLimit`; nil when it has none.
    /// Claude Code writes "(no content)" for an empty one.
    static func text(of message: [String: Any]) -> String? {
        let blocks = message["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "(no content)" else { return nil }
        return text.count > messageLimit ? String(text.prefix(messageLimit)) + "…" : text
    }
}
