import Foundation

/// Something that happened in the herd, delivered to subscribers in order. Transitions are what
/// the sources observed; a task start is Shepherd's own action, which no source reports.
public enum HerdEvent: Sendable, Equatable {
    case transitions([HerdTransition])
    /// A task was started: its new agent and the project it was started in.
    case taskStarted(AgentID, ProjectID)
}
