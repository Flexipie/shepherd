import Foundation

/// One agent as Shepherd shows it.
public struct AgentState: Sendable, Equatable, Identifiable {
    public let agent: Agent
    public let workspaceLabel: String
    public let since: StateSince?

    public var id: String { agent.id }
    public var status: AgentStatus { agent.status }
}

/// An immutable view of herdr's state plus what Shepherd derives from it.
public struct Session: Sendable, Equatable {
    public let snapshot: SessionSnapshot
    /// Agents in herdr's workspace order.
    public let agents: [AgentState]
    /// Agents waiting on the user: blocked first, then finished and unseen, longest waiting first.
    public let needsYou: [AgentState]
    public let workingCount: Int

    public static let empty = Session(snapshot: .empty, tracker: TransitionTracker())

    public init(snapshot: SessionSnapshot, tracker: TransitionTracker) {
        self.snapshot = snapshot
        let labels = Dictionary(snapshot.workspaces.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(snapshot.workspaces.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        agents = snapshot.agents
            .map { AgentState(agent: $0, workspaceLabel: labels[$0.workspaceID] ?? "", since: tracker.since($0.id)) }
            .sorted { (order[$0.agent.workspaceID] ?? .max, $0.id) < (order[$1.agent.workspaceID] ?? .max, $1.id) }
        needsYou = agents.filter(\.status.needsYou).sorted(by: Self.waitingOrder)
        workingCount = agents.count { $0.status == .working }
    }

    public func agent(_ paneID: String) -> AgentState? {
        agents.first { $0.id == paneID }
    }

    private static func waitingOrder(_ a: AgentState, _ b: AgentState) -> Bool {
        if (a.status == .blocked) != (b.status == .blocked) { return a.status == .blocked }
        switch (a.since?.date, b.since?.date) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.id < b.id
        }
    }
}
