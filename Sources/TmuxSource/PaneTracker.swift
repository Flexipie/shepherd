import Foundation
import ShepherdCore

/// One agent pane as the last scan or screen read saw it.
struct PaneObservation: Equatable {
    /// The agent's identity, `tmux:<socket>:<pane>`: the same key `ReportIdentity` gives a pane.
    let key: String
    let socket: String
    let paneID: String
    let windowID: String
    let session: String
    let kind: String
    /// The pane's folder, possibly empty.
    let path: String
    let isFocused: Bool
    /// The state the screen showed at the last read, before settling.
    var status: HerdStatus
    /// When the last read showed `working`, nil otherwise.
    var workingSeen: Date?

    /// The same key `ReportIdentity` gives a pane, so a report and a screen reading of one pane meet.
    static func key(socket: String, paneID: String) -> String {
        "tmux:\(socket):\(paneID)"
    }
}

/// Turns screen readings into the agents the herd shows and says what changed. Pure: the caller
/// passes every current observation and the time, so each rule is tested with an injected `now`.
///
/// A reading is noisy: a redraw can show neither marker for a moment. So a change waits until the
/// new state holds for `settle`, except that a prompt waiting for an answer shows at once. A
/// `working` reading also goes stale when no read has seen it for `quietLimit`, the same rule as
/// `ReportTracker`.
struct PaneTracker {
    static let settle: TimeInterval = 2
    static let quietLimit: TimeInterval = 15 * 60
    static let source: SourceID = "tmux"

    struct Entry: Equatable {
        var shown: HerdStatus
        /// When `shown` began.
        var since: Date
        /// A different state the screen now shows, and since when, not yet held for `settle`.
        var pending: Pending?
        /// The pane as it was last seen, kept so its going away can say what it was.
        var observation: PaneObservation
    }

    struct Pending: Equatable {
        var status: HerdStatus
        var since: Date
    }

    struct Outcome: Equatable {
        var agents: [HerdAgent]
        var projects: [HerdProject]
        /// Changes since the previous call. Empty for the first call, which is the baseline.
        var transitions: [HerdTransition]
        /// The next time the outcome changes with no new reading: a pending change settling, or a
        /// working reading going stale.
        var nextDeadline: Date?
    }

    private(set) var entries: [String: Entry] = [:]
    private var hasBaseline = false

    /// The state the herd shows for an agent, if it is known.
    func shown(_ key: String) -> HerdStatus? {
        entries[key]?.shown
    }

    mutating func apply(_ observations: [PaneObservation], at now: Date) -> Outcome {
        let current = Dictionary(observations.map { ($0.key, $0) }) { first, _ in first }
        var transitions: [HerdTransition] = []
        var deadlines: [Date] = []

        for key in current.keys.sorted() {
            guard let observation = current[key] else { continue }
            let target = Self.target(observation, at: now)
            guard var entry = entries[key] else {
                entries[key] = Entry(shown: target, since: now, pending: nil, observation: observation)
                if hasBaseline {
                    transitions.append(Self.transition(observation, from: nil, to: target, at: now))
                }
                continue
            }
            entry.observation = observation
            if target == entry.shown {
                entry.pending = nil
            } else if target == .blocked {
                transitions.append(Self.transition(observation, from: entry.shown, to: target, at: now))
                entry.shown = target
                entry.since = now
                entry.pending = nil
            } else if let pending = entry.pending, pending.status == target {
                if now.timeIntervalSince(pending.since) >= Self.settle {
                    transitions.append(Self.transition(observation, from: entry.shown, to: target, at: pending.since))
                    entry.shown = target
                    entry.since = pending.since
                    entry.pending = nil
                }
            } else {
                entry.pending = Pending(status: target, since: now)
            }
            if let pending = entry.pending {
                deadlines.append(pending.since.addingTimeInterval(Self.settle))
            }
            if observation.status == .working, let seen = observation.workingSeen {
                deadlines.append(seen.addingTimeInterval(Self.quietLimit))
            }
            entries[key] = entry
        }

        for key in entries.keys.sorted() where current[key] == nil {
            guard let entry = entries[key] else { continue }
            if hasBaseline {
                transitions.append(Self.transition(entry.observation, from: entry.shown, to: nil, at: now))
            }
            entries[key] = nil
        }
        hasBaseline = true

        let shown = entries.keys.sorted().compactMap { entries[$0] }
        return Outcome(agents: shown.map(Self.agent),
                       projects: Self.projects(shown.map(\.observation)),
                       transitions: transitions.sorted { $0.agent.local < $1.agent.local },
                       nextDeadline: deadlines.filter { $0 > now }.min())
    }

    /// The status a reading gives at `now`: working goes unknown once it has not been seen for `quietLimit`.
    static func target(_ observation: PaneObservation, at now: Date) -> HerdStatus {
        guard observation.status == .working else { return observation.status }
        guard let seen = observation.workingSeen else { return .unknown }
        return now < seen.addingTimeInterval(quietLimit) ? .working : .unknown
    }

    private static func transition(_ observation: PaneObservation, from: HerdStatus?, to: HerdStatus?, at: Date) -> HerdTransition {
        HerdTransition(agent: AgentID(source: source, local: observation.key), kind: observation.kind,
                       project: projectName(observation.path), from: from, to: to, at: at)
    }

    private static func agent(_ entry: Entry) -> HerdAgent {
        let observation = entry.observation
        return HerdAgent(id: AgentID(source: source, local: observation.key), kind: observation.kind,
                         name: observation.kind,
                         projectID: observation.path.isEmpty ? nil : ProjectID(source: source, local: observation.path),
                         project: projectName(observation.path), status: entry.shown, since: Since(entry.since, .exact),
                         isFocusedInSource: observation.isFocused, isInferred: true)
    }

    /// One project per distinct folder, in the agents' order.
    private static func projects(_ observations: [PaneObservation]) -> [HerdProject] {
        var seen = Set<String>()
        var projects: [HerdProject] = []
        for observation in observations where !observation.path.isEmpty && seen.insert(observation.path).inserted {
            projects.append(HerdProject(id: ProjectID(source: source, local: observation.path),
                                        name: projectName(observation.path), path: observation.path, isInferred: true))
        }
        return projects
    }

    static func projectName(_ path: String) -> String {
        path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
    }
}
