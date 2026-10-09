import Foundation

/// Observed transitions, kept on disk so history survives restarts: the timeline, recap and
/// attention ideas build on it, and sources use it to restore exact times in state. One JSON line
/// per transition, appended only when transitions happen, capped by compacting to the newest
/// `capacity` entries once the file holds twice that. Local only; it never leaves the Mac.
public actor TransitionLog {
    public let url: URL
    public let capacity: Int
    private var lineCount: Int?

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Shepherd/transitions.jsonl")
    }

    public init(url: URL = TransitionLog.defaultURL, capacity: Int = 5000) {
        self.url = url
        self.capacity = capacity
    }

    /// Every readable entry, oldest first. Unreadable lines are skipped.
    public func load() -> [HerdTransition] {
        guard let data = try? Data(contentsOf: url) else {
            lineCount = 0
            return []
        }
        let lines = data.split(separator: 0x0A)
        lineCount = lines.count
        let decoder = Self.decoder
        return lines.compactMap { try? decoder.decode(HerdTransition.self, from: Data($0)) }
    }

    /// The newest entry for each agent.
    public func latestByAgent() -> [AgentID: HerdTransition] {
        var latest: [AgentID: HerdTransition] = [:]
        for entry in load() { latest[entry.agent] = entry }
        return latest
    }

    public func append(_ transitions: [HerdTransition]) {
        guard !transitions.isEmpty else { return }
        if lineCount == nil { _ = load() }
        var data = Data()
        let encoder = Self.encoder
        for transition in transitions {
            guard let line = try? encoder.encode(transition) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
            lineCount = (lineCount ?? 0) + transitions.count
            if let count = lineCount, count >= capacity * 2 { compact() }
        } catch {
            // History is a nice-to-have; never let a full disk or a permission problem break the app.
        }
    }

    private func compact() {
        guard let data = try? Data(contentsOf: url) else { return }
        let kept = data.split(separator: 0x0A).suffix(capacity)
        var output = Data()
        for line in kept {
            output.append(contentsOf: line)
            output.append(0x0A)
        }
        if (try? output.write(to: url, options: .atomic)) != nil { lineCount = kept.count }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
