import Foundation

/// What a plugin's action acts on.
public enum PluginTarget: Sendable, Hashable {
    case global
    case project(ProjectID)
    case agent(AgentID)
}

/// Which plugin action to run on what. Carried by a palette item, so it is plain ids.
public struct PluginActionRef: Sendable, Hashable {
    public let plugin: String
    public let action: String
    public let target: PluginTarget

    public init(plugin: String, action: String, target: PluginTarget) {
        self.plugin = plugin
        self.action = action
        self.target = target
    }
}

/// Runs a plugin's command. The app's runs a process; tests supply their own.
public protocol PluginRunner: Sendable {
    /// Runs `command` from `folder` with `environment` added to the app's. Throws when it cannot
    /// start or runs past `timeout`; a non-zero exit is a result, not an error.
    func run(_ command: [String], in folder: URL, environment: [String: String], timeout: Duration) async throws -> PluginRunResult
}

public struct PluginRunResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// What a command printed: plain text is the result; a JSON object is applied.
public struct PluginOutput: Sendable, Equatable {
    /// Shown to the user, if anything.
    public var text: String?
    /// Tokens to set on the target; nil removes one.
    public var tokens: [String: String?]

    public init(text: String? = nil, tokens: [String: String?] = [:]) {
        self.text = text
        self.tokens = tokens
    }

    public static func parse(_ stdout: String) -> PluginOutput {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), case .table(let table)? = try? JSONDecoder().decode(ConfigValue.self, from: Data(trimmed.utf8)) else {
            return PluginOutput(text: trimmed.isEmpty ? nil : trimmed)
        }
        var output = PluginOutput()
        if case .string(let text)? = table["text"], !text.isEmpty { output.text = text }
        if case .table(let tokens)? = table["tokens"] {
            for (key, value) in tokens {
                switch value {
                case .string(let text): output.tokens[key] = text.isEmpty ? .some(nil) : .some(text)
                case .number(let number): output.tokens[key] = .some(number.rounded() == number ? String(Int(number)) : String(number))
                case .null: output.tokens[key] = .some(nil)
                default: continue
                }
            }
        }
        return output
    }
}

extension PluginTarget {
    /// The environment a command gets for this target, from what the herd knows now.
    @MainActor
    func environment(store: HerdStore, tokens: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        func add(_ project: HerdProject) {
            env["SHEPHERD_PROJECT_ID"] = project.id.description
            env["SHEPHERD_PROJECT_NAME"] = project.name
            if let path = project.path { env["SHEPHERD_PROJECT_PATH"] = path }
            if let repo = project.repo { env["SHEPHERD_REPO_NAME"] = repo.name }
        }
        switch self {
        case .global: break
        case .project(let id):
            if let project = store.projects.first(where: { $0.id == id }) { add(project) }
        case .agent(let id):
            guard let agent = store.agents.first(where: { $0.id == id }) else { break }
            env["SHEPHERD_AGENT_ID"] = id.description
            env["SHEPHERD_AGENT_NAME"] = agent.name
            env["SHEPHERD_AGENT_STATUS"] = agent.statusText
            if let kind = agent.kind { env["SHEPHERD_AGENT_KIND"] = kind }
            if let session = agent.session {
                env["SHEPHERD_SESSION_ID"] = session.id
                if let cwd = session.cwd { env["SHEPHERD_CWD"] = cwd }
            }
            if let project = agent.projectID.flatMap({ id in store.projects.first { $0.id == id } }) { add(project) }
        }
        if env["SHEPHERD_CWD"] == nil, let path = env["SHEPHERD_PROJECT_PATH"] { env["SHEPHERD_CWD"] = path }
        if self != .global, let data = try? JSONSerialization.data(withJSONObject: tokens, options: [.sortedKeys]) {
            env["SHEPHERD_TOKENS"] = String(decoding: data, as: UTF8.self)
        }
        return env
    }
}
