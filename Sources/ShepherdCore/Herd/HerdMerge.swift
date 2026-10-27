import Foundation

/// One agent seen by two sources, such as a Claude Code session in a tmux pane that also reports
/// through its hooks. The herd shows it as one row: the host's, so actions go to the source that
/// can act on it, with the state from whichever side reads it best.
struct HerdMerge: Equatable {
    /// The agent whose row is shown: its source can do more with it.
    let host: AgentID
    /// The agent folded into the host's row.
    let guest: AgentID
    /// The row's state comes from the guest: the host only read it from a screen and the guest did not.
    let stateFromGuest: Bool
    /// The host's kind and project name, so the guest's changes are told as the row's.
    var hostKind: String? = nil
    var hostProject = ""

    /// Pairs of agents from different sources that are one process: a screen reading and a report
    /// with the same key (`tmux:<socket>:<pane>`, which both give a pane), or two agents with the
    /// same session (a report from a hook and herdr's agent for that session). Other local ids are
    /// each source's own and say nothing. Each agent is in at most one pair.
    static func find(in agents: [HerdAgent], capabilities: (SourceID) -> SourceCapabilities) -> [HerdMerge] {
        var merges: [HerdMerge] = []
        var paired = Set<AgentID>()
        for (index, first) in agents.enumerated() where !paired.contains(first.id) {
            guard let second = agents[(index + 1)...].first(where: { other in
                !paired.contains(other.id) && other.id.source != first.id.source && isSameProcess(first, other)
            }) else { continue }
            let firstCount = capabilities(first.id.source).rawValue.nonzeroBitCount
            let secondCount = capabilities(second.id.source).rawValue.nonzeroBitCount
            let (host, guest) = secondCount > firstCount ? (second, first) : (first, second)
            merges.append(HerdMerge(host: host.id, guest: guest.id, stateFromGuest: host.isInferred && !guest.isInferred,
                                    hostKind: host.kind ?? guest.kind, hostProject: host.project))
            paired.formUnion([first.id, second.id])
        }
        return merges
    }

    /// Agents of different kinds never pair: a report left behind in a pane number tmux reuses
    /// after a restart must not lend its state to another agent there.
    private static func isSameProcess(_ a: HerdAgent, _ b: HerdAgent) -> Bool {
        if let x = a.kind, let y = b.kind, x != y { return false }
        if a.isInferred != b.isInferred, a.id.local == b.id.local { return true }
        guard let x = a.session, let y = b.session else { return false }
        return x.kind == y.kind && x.id == y.id
    }

    /// The host's row with what the guest knows better: its state, message and question when it
    /// gives the state, else only what the host lacks.
    func row(host: HerdAgent, guest: HerdAgent) -> HerdAgent {
        let state = stateFromGuest ? guest : host
        let other = stateFromGuest ? host : guest
        return HerdAgent(
            id: host.id, kind: host.kind ?? guest.kind, name: host.name, projectID: host.projectID,
            project: host.project, status: state.status, statusLabel: state.statusLabel, since: state.since,
            tokens: host.tokens, isFocusedInSource: host.isFocusedInSource, session: host.session ?? guest.session,
            message: state.message ?? other.message, question: state.question ?? other.question,
            cwd: host.cwd ?? guest.cwd, isInferred: state.isInferred)
    }

    /// The transition as the merged row sees it, or nil when the other side's describes the row.
    /// The host's appearing and going are the row's; the guest's are not, since the host's row was
    /// there before and stays.
    func view(of transition: HerdTransition) -> HerdTransition? {
        let changesState = transition.from != nil && transition.to != nil
        if transition.agent == host { return stateFromGuest && changesState ? nil : transition }
        guard transition.agent == guest, stateFromGuest, changesState else { return nil }
        return HerdTransition(agent: host, kind: hostKind ?? transition.kind, project: hostProject, from: transition.from,
                              to: transition.to, at: transition.at, precision: transition.precision,
                              marker: transition.marker)
    }
}
