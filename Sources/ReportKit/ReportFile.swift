import Foundation

/// One agent's report as it sits in the spool: one JSON file per agent, written by `shepherd report`
/// and read by `ReportSource`. Holds no Shepherd types, so any tool can read or write the format.
public struct ReportFile: Sendable, Equatable {
    public static let currentVersion = 1
    /// Messages longer than this many bytes are cut at a character boundary.
    public static let messageLimit = 4096

    /// What the agent says it is doing. `closed` means the agent is gone and its file is removed.
    public enum Status: String, Sendable, CaseIterable {
        case working, blocked, done, idle, closed
    }

    public let version: Int
    /// The agent's key, such as `tmux:/tmp/tmux-501/default:%3` or a name from `--agent`.
    public let agent: String
    public let status: Status
    public let message: String?
    public let question: String?
    /// The kind of agent, such as `claude`, when the reporter gave one.
    public let kind: String?
    /// The agent's working directory, when known.
    public let cwd: String?
    public let updatedAt: Date

    public init(agent: String, status: Status, message: String? = nil, question: String? = nil, kind: String? = nil,
                cwd: String? = nil, updatedAt: Date) {
        version = Self.currentVersion
        self.agent = agent
        self.status = status
        self.message = message.map { Self.clip($0, toBytes: Self.messageLimit) }
        self.question = question.map { Self.clip($0, toBytes: Self.messageLimit) }
        self.kind = kind
        self.cwd = cwd
        self.updatedAt = updatedAt
    }

    /// Reads one report. Unknown keys are ignored and optional keys may be missing. A file that
    /// lacks what the report needs, or has a status or version this build does not know, throws.
    public static func decode(_ data: Data) throws -> ReportFile {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ReportProblem("not JSON")
        }
        guard let object = parsed as? [String: Any] else {
            throw ReportProblem("not a JSON object")
        }
        guard let version = object["version"] as? Int, version == currentVersion else {
            throw ReportProblem("unsupported version")
        }
        guard let agent = object["agent"] as? String, !agent.isEmpty else {
            throw ReportProblem("no agent")
        }
        guard let rawStatus = object["status"] as? String, let status = Status(rawValue: rawStatus) else {
            throw ReportProblem("unknown status")
        }
        guard let updated = object["updatedAt"] as? String, let updatedAt = ReportDate.parse(updated) else {
            throw ReportProblem("no valid updatedAt")
        }
        return ReportFile(agent: agent, status: status, message: object["message"] as? String,
                          question: object["question"] as? String, kind: object["kind"] as? String,
                          cwd: object["cwd"] as? String, updatedAt: updatedAt)
    }

    /// The file's bytes: sorted keys, ISO 8601 time with fractional seconds.
    public func encoded() throws -> Data {
        var object: [String: Any] = [
            "version": version, "agent": agent, "status": status.rawValue,
            "updatedAt": ReportDate.string(from: updatedAt),
        ]
        object["message"] = message
        object["question"] = question
        object["kind"] = kind
        object["cwd"] = cwd
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// The longest prefix of `text` that fits in `limit` bytes, cut at a character boundary.
    static func clip(_ text: String, toBytes limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        var clipped = ""
        var bytes = 0
        for character in text {
            let size = character.utf8.count
            if bytes + size > limit { break }
            clipped.append(character)
            bytes += size
        }
        return clipped
    }

}

/// Why a report file could not be used. The message says what is wrong, in words.
public struct ReportProblem: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// ISO 8601 with fractional seconds, reading either form. A formatter is made per call: they are
/// not safe to share across threads, and reports are few and small.
enum ReportDate {
    static func string(from date: Date) -> String {
        makeFormatter(fractional: true).string(from: date)
    }

    static func parse(_ text: String) -> Date? {
        makeFormatter(fractional: true).date(from: text) ?? makeFormatter(fractional: false).date(from: text)
    }

    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }
}
