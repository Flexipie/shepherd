import Foundation

/// Diffs consecutive snapshots into transitions and keeps, per agent, when its current state
/// began. Pure: no I/O, no clock; the caller passes the time.
public struct TransitionTracker: Sendable {
    struct Record: Sendable, Equatable {
        var terminalID: String?
        var status: AgentStatus
        var stateChangeSeq: UInt64
        var completionSeq: UInt64
        var since: StateSince
    }

    /// A state time remembered from an earlier run. Used once, on first sight of the pane, and
    /// only if the pane still has the same terminal and change counter: then nothing happened in
    /// between and the earlier time is still true.
    public struct Seed: Sendable, Equatable {
        public let paneID: String
        public let terminalID: String?
        public let stateChangeSeq: UInt64
        public let since: StateSince

        public init(paneID: String, terminalID: String?, stateChangeSeq: UInt64, since: StateSince) {
            self.paneID = paneID
            self.terminalID = terminalID
            self.stateChangeSeq = stateChangeSeq
            self.since = since
        }
    }

    private(set) var records: [String: Record] = [:]
    private var hasBaseline = false
    private var seeds: [String: Seed]

    public init(seeds: [Seed] = []) {
        self.seeds = Dictionary(seeds.map { ($0.paneID, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func since(_ paneID: String) -> StateSince? {
        records[paneID]?.since
    }

    public mutating func apply(_ snapshot: SessionSnapshot, at now: Date, continuity: Continuity) -> [Transition] {
        let precision: StateSince.Precision = continuity == .continuous ? .exact : .noLaterThan
        var transitions: [Transition] = []
        var seen = Set<String>()

        for agent in snapshot.agents {
            seen.insert(agent.id)
            let completion = agent.completionSeq ?? 0
            let fresh = Record(terminalID: agent.terminalID, status: agent.status, stateChangeSeq: agent.stateChangeSeq,
                               completionSeq: completion, since: StateSince(now, precision))

            guard let old = records[agent.id] else {
                // Never seen. Only a continuous stream after the first snapshot proves it just appeared.
                let seed = seeds.removeValue(forKey: agent.id)
                if hasBaseline, continuity == .continuous {
                    transitions.append(Transition(paneID: agent.id, kind: .appeared, from: nil, to: agent.status,
                                                  observedAt: now, terminalID: agent.terminalID,
                                                  stateChangeSeq: agent.stateChangeSeq))
                    records[agent.id] = fresh
                } else if let seed, seed.terminalID == agent.terminalID, seed.stateChangeSeq == agent.stateChangeSeq {
                    records[agent.id] = Record(terminalID: fresh.terminalID, status: fresh.status,
                                               stateChangeSeq: fresh.stateChangeSeq, completionSeq: completion,
                                               since: seed.since)
                } else {
                    records[agent.id] = Record(terminalID: fresh.terminalID, status: fresh.status,
                                               stateChangeSeq: fresh.stateChangeSeq, completionSeq: completion,
                                               since: StateSince(now, .noLaterThan))
                }
                continue
            }

            // A different occupant or a reset counter (herdr restarted, pane id reused): start over.
            if old.terminalID != agent.terminalID || agent.stateChangeSeq < old.stateChangeSeq {
                records[agent.id] = Record(terminalID: fresh.terminalID, status: fresh.status,
                                           stateChangeSeq: fresh.stateChangeSeq, completionSeq: completion,
                                           since: StateSince(now, .noLaterThan))
                continue
            }

            guard agent.stateChangeSeq > old.stateChangeSeq || agent.status != old.status else { continue }
            let seqDelta = agent.stateChangeSeq - old.stateChangeSeq
            transitions.append(Transition(
                paneID: agent.id, kind: .changed, from: old.status, to: agent.status, observedAt: now,
                missedChanges: seqDelta > 1 ? seqDelta - 1 : 0,
                completedTurns: completion > old.completionSeq ? completion - old.completionSeq : 0,
                terminalID: agent.terminalID, stateChangeSeq: agent.stateChangeSeq))
            records[agent.id] = fresh
        }

        for (paneID, old) in records where !seen.contains(paneID) {
            transitions.append(Transition(paneID: paneID, kind: .closed, from: old.status, to: nil, observedAt: now,
                                          terminalID: old.terminalID, stateChangeSeq: old.stateChangeSeq))
            records[paneID] = nil
        }
        hasBaseline = true
        return transitions.sorted { $0.paneID < $1.paneID }
    }
}
