import Foundation

/// Rewrites recorded herdr JSON so no real path, title, label or id reaches the repo. Works on
/// raw JSON, so fields herdr adds later are scrubbed too: every string is replaced unless its key
/// is on a short allow-list of enum-like values. Replacements are consistent (the same input
/// gives the same output), so ids still line up across workspaces, panes and agents.
public struct Sanitiser {
    /// Keys whose string values are vocabulary, not user data.
    static let keep: Set<String> = ["agent_status", "agent", "type", "event", "kind", "version", "source_kind"]
    /// Id families: every key in a family shares one mapping.
    static let idFamilies: [String: String] = [
        "workspace_id": "w", "focused_workspace_id": "w",
        "tab_id": "t", "active_tab_id": "t", "focused_tab_id": "t",
        "pane_id": "p", "focused_pane_id": "p", "previous_pane_id": "p",
        "terminal_id": "term",
    ]
    static let pathKeys: Set<String> = ["cwd", "foreground_cwd", "path", "root", "repo_root", "manifest_path", "plugin_root"]
    /// Objects whose keys are names chosen by herdr or plugins (kept) with user values (scrubbed).
    static let mapKeys: Set<String> = ["tokens", "state_labels"]

    private var mappings: [String: [String: String]] = [:]

    public init() {}

    public mutating func sanitise(_ value: Any, key: String? = nil) -> Any {
        switch value {
        case let object as [String: Any]:
            var result: [String: Any] = [:]
            for (childKey, child) in object {
                let contextKey = key.map { Self.mapKeys.contains($0) } == true ? "\(key!).value" : childKey
                result[childKey] = sanitise(child, key: contextKey)
            }
            return result
        case let array as [Any]:
            return array.map { sanitise($0, key: key) }
        case let string as String:
            return sanitise(string: string, key: key ?? "value")
        default:
            return value
        }
    }

    private mutating func sanitise(string: String, key: String) -> String {
        if Self.keep.contains(key) || string.isEmpty { return string }
        let family = Self.idFamilies[key] ?? (Self.pathKeys.contains(key) ? "path" : key)
        if let existing = mappings[family]?[string] { return existing }
        let number = (mappings[family]?.count ?? 0) + 1
        let replacement = switch family {
        case "path": "/tmp/project-\(number)"
        case "w", "t", "p", "term": "\(family)\(number)"
        default: "\(family.replacingOccurrences(of: ".value", with: ""))-\(number)"
        }
        mappings[family, default: [:]][string] = replacement
        return replacement
    }
}

/// Recorded, sanitised herdr output: one snapshot result and the events that followed.
public struct RecordedFixture: Sendable {
    /// The `session.snapshot` result's `snapshot` object, as JSON.
    public let snapshot: Data
    /// Pushed event lines, as JSON.
    public let events: [Data]

    public init(snapshot: Data, events: [Data]) {
        self.snapshot = snapshot
        self.events = events
    }

    /// Loads `Fixtures/<name>.json` from this module's resources.
    public static func named(_ name: String) throws -> RecordedFixture {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> RecordedFixture {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshot = object["snapshot"] else { throw CocoaError(.coderReadCorrupt) }
        let events = (object["events"] as? [Any] ?? []).compactMap { try? JSONSerialization.data(withJSONObject: $0) }
        return RecordedFixture(snapshot: try JSONSerialization.data(withJSONObject: snapshot), events: events)
    }

    public func encoded() throws -> Data {
        let object: [String: Any] = [
            "snapshot": try JSONSerialization.jsonObject(with: snapshot),
            "events": try events.map { try JSONSerialization.jsonObject(with: $0) },
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
