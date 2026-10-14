import Foundation
import ShepherdCore

/// Reads a Claude Code agent's context size from its session file:
/// `<config>/projects/<cwd, every non-alphanumeric character as "-">/<session id>.jsonl`, where
/// `<config>` is `CLAUDE_CONFIG_DIR` or `~/.claude`. When that file is missing (the agent changed
/// directory), it looks for `<session id>.jsonl` in every project folder once and remembers it.
///
/// Read-only, and only the file's last `tailBytes`. The size is the last main-thread assistant
/// turn's input plus cache read plus cache creation tokens. An unchanged file (same size and
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

    public func contextTokens(for session: AgentSession) async throws -> Int? {
        guard session.kind == "claude", ClaudeSessionFile.isSafeID(session.id) else { return nil }
        let expected = session.cwd.map { projects.appending(path: ClaudeSessionFile.folderName($0)).appending(path: "\(session.id).jsonl") }
        let candidates = [paths[session.id], expected].compactMap { $0 }
        let result = try await ClaudeSessionFile.locateAndRead(id: session.id, candidates: candidates, projects: projects,
                                                               cache: cache, tailBytes: Self.tailBytes)
        paths[session.id] = result?.url
        guard let result else { return nil }
        cache[result.url] = result.reading
        return result.reading.tokens
    }
}

/// The file work behind `ClaudeContextReader`, free of any actor so it runs off the main one.
enum ClaudeSessionFile {
    /// One read of a session file, kept so an unchanged file is not read again.
    struct Reading: Sendable, Equatable {
        let size: UInt64
        let modified: Date
        let tokens: Int?
    }

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
        return Reading(size: size, modified: modified, tokens: lastContextTokens(in: data, cutAtStart: offset > 0))
    }

    /// Walks the lines from the end to the last assistant turn of the main thread (not a
    /// sidechain, not a synthetic error) with usage. `cutAtStart` drops the first line, which the
    /// tail window may have cut.
    static func lastContextTokens(in data: Data, cutAtStart: Bool) -> Int? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if cutAtStart, !lines.isEmpty { lines.removeFirst() }
        let marker = Data(#""assistant""#.utf8)
        for line in lines.reversed() where line.range(of: marker) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any], message["model"] as? String != "<synthetic>",
                  let usage = message["usage"] as? [String: Any] else { continue }
            let keys = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            let total = keys.reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
            if total > 0 { return total }
        }
        return nil
    }
}
