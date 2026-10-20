import Foundation

/// The events a plugin can list under `events` in its manifest.
public enum PluginEvent: String, Sendable, Equatable, CaseIterable {
    case agentStarted = "agent.started"
    case agentBlocked = "agent.blocked"
    case agentFinished = "agent.finished"
    case taskStarted = "task.started"
}

/// One entry of a manifest's `events`: the events it runs for, and the command it runs.
public struct PluginEventRule: Sendable, Equatable {
    public let on: [PluginEvent]
    /// The program and its arguments, run from the plugin's folder.
    public let command: [String]

    public init(on: [PluginEvent], command: [String]) {
        self.on = on
        self.command = command
    }

    /// Reads a list of rules, skipping the ones that cannot be used.
    static func list(_ value: ConfigValue?, at path: String, problems: inout [String]) -> [PluginEventRule] {
        guard let value else { return [] }
        guard case .array(let items) = value else {
            problems.append("\(path) must be a list")
            return []
        }
        return items.enumerated().compactMap { index, item in
            let here = "\(path)[\(index)]"
            guard case .table(let table) = item, case .array(let names)? = table["on"],
                  let command = table["command"].flatMap(PluginAction.command) else {
                problems.append("\(here) needs \"on\" (a list of event names) and a command (a list of strings)")
                return nil
            }
            let strings = names.compactMap { name -> String? in if case .string(let s) = name { s } else { nil } }
            let events = strings.compactMap(PluginEvent.init(rawValue:))
            if events.count != names.count {
                let known = PluginEvent.allCases.map(\.rawValue).joined(separator: ", ")
                problems.append("\(here).on has names that are not events (known: \(known))")
            }
            guard !events.isEmpty else { return nil }
            return PluginEventRule(on: events, command: command)
        }
    }
}

/// An event for one agent, or for a project when a task starts (the new agent is still named, so
/// the command can find it). `target` is what the command's environment describes.
public struct PluginEventOccurrence: Sendable, Equatable {
    public let event: PluginEvent
    public let agent: AgentID
    public let target: PluginTarget

    public init(event: PluginEvent, agent: AgentID, target: PluginTarget) {
        self.event = event
        self.agent = agent
        self.target = target
    }

    /// The occurrences a herd event raises. An agent that appears raises `agent.started`; a
    /// status change to blocked or done raises the matching event; an agent that goes away raises
    /// nothing.
    public static func raised(by event: HerdEvent) -> [PluginEventOccurrence] {
        switch event {
        case .taskStarted(let agent, let project):
            return [PluginEventOccurrence(event: .taskStarted, agent: agent, target: .project(project))]
        case .transitions(let transitions):
            return transitions.compactMap { transition in
                let kind: PluginEvent
                if transition.from == nil {
                    guard transition.to != nil else { return nil }
                    kind = .agentStarted
                } else {
                    switch transition.to {
                    case .blocked?: kind = .agentBlocked
                    case .done?: kind = .agentFinished
                    default: return nil
                    }
                }
                return PluginEventOccurrence(event: kind, agent: transition.agent, target: .agent(transition.agent))
            }
        }
    }
}
