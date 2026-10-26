import Foundation
import ReportKit
import ShepherdCore

/// Maps the spool's reports to the herd model and says what changed. Pure: the caller passes the
/// reports and the time, so every rule is tested with an injected `now`.
struct ReportTracker {
    /// A working report older than this shows as unknown. A long build sends no hook, so silence is
    /// not stale yet, but it is not evidence of work either.
    static let quietLimit: TimeInterval = 15 * 60
    /// A blocked or done report older than this is removed from the herd and its file deleted.
    static let retention: TimeInterval = 24 * 60 * 60
    static let source: SourceID = "report"

    struct Entry: Equatable {
        var status: HerdStatus
        /// When `status` began.
        var since: Date
        var report: ReportFile
    }

    struct Outcome: Equatable {
        var agents: [HerdAgent]
        var projects: [HerdProject]
        /// Changes since the previous call. Empty for the first call, which is the baseline.
        var transitions: [HerdTransition]
        /// Agent keys whose files should be removed from the spool.
        var expired: [String]
        /// The next time the outcome changes with no new report: a working report going quiet, or a
        /// report expiring.
        var nextDeadline: Date?
    }

    private(set) var entries: [String: Entry] = [:]
    private var hasBaseline = false

    mutating func apply(_ reports: [ReportFile], at now: Date) -> Outcome {
        var seen = Set<String>()
        var expired: [String] = []
        var transitions: [HerdTransition] = []
        var deadlines: [Date] = []

        // When a key appears twice, the newer report counts.
        let latest = Dictionary(reports.map { ($0.agent, $0) }) { first, second in
            first.updatedAt >= second.updatedAt ? first : second
        }
        for (key, report) in latest {
            if report.status == .closed {
                expired.append(key)
                continue
            }
            if (report.status == .blocked || report.status == .done),
               now >= report.updatedAt.addingTimeInterval(Self.retention) {
                expired.append(key)
                continue
            }
            seen.insert(key)
            let (status, began) = Self.state(of: report, at: now)
            let old = entries[key]
            if old?.status != status, hasBaseline {
                transitions.append(Self.transition(key, report, from: old?.status, to: status, at: now))
            }
            // A new report with the same status keeps the time the status began.
            var since = began
            if let old, old.status == status { since = old.since }
            entries[key] = Entry(status: status, since: since, report: report)

            switch report.status {
            case .working where status == .working:
                deadlines.append(report.updatedAt.addingTimeInterval(Self.quietLimit))
            case .blocked, .done:
                deadlines.append(report.updatedAt.addingTimeInterval(Self.retention))
            default:
                break
            }
        }

        for (key, old) in entries.filter({ !seen.contains($0.key) }) {
            if hasBaseline {
                transitions.append(Self.transition(key, old.report, from: old.status, to: nil, at: now))
            }
            entries[key] = nil
        }
        hasBaseline = true

        let sorted = entries.sorted { $0.key < $1.key }
        return Outcome(
            agents: sorted.map { key, entry in Self.agent(key, entry) },
            projects: Self.projects(sorted.map(\.value)),
            transitions: transitions.sorted { $0.agent.local < $1.agent.local },
            expired: expired.sorted(),
            nextDeadline: deadlines.filter { $0 > now }.min())
    }

    /// The status a report shows at `now`, and when that status began.
    static func state(of report: ReportFile, at now: Date) -> (HerdStatus, Date) {
        switch report.status {
        case .working:
            let quietAt = report.updatedAt.addingTimeInterval(quietLimit)
            return now < quietAt ? (.working, report.updatedAt) : (.unknown, quietAt)
        case .blocked: return (.blocked, report.updatedAt)
        case .done: return (.done, report.updatedAt)
        case .idle: return (.idle, report.updatedAt)
        // Closed reports are removed before they reach here.
        case .closed: return (.unknown, report.updatedAt)
        }
    }

    /// A row's name: the key itself when someone gave it by hand, else the agent's kind.
    static func name(key: String, kind: String?) -> String {
        let generated = ["tmux:", "session:", "cwd:"].contains { key.hasPrefix($0) }
        return generated ? (kind ?? "agent") : key
    }

    /// The last path component of the agent's folder, or nothing when the report had no folder.
    static func projectName(_ report: ReportFile) -> String {
        report.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
    }

    private static func agent(_ key: String, _ entry: Entry) -> HerdAgent {
        HerdAgent(
            id: AgentID(source: source, local: key), kind: entry.report.kind,
            name: name(key: key, kind: entry.report.kind),
            projectID: entry.report.cwd.map { ProjectID(source: source, local: $0) },
            project: projectName(entry.report), status: entry.status, since: Since(entry.since, .exact),
            message: entry.report.message, question: entry.report.question)
    }

    private static func transition(_ key: String, _ report: ReportFile, from: HerdStatus?, to: HerdStatus?,
                                   at now: Date) -> HerdTransition {
        HerdTransition(agent: AgentID(source: source, local: key), kind: report.kind,
                       project: projectName(report), from: from, to: to, at: now)
    }

    /// One project per distinct folder, in the agents' order.
    private static func projects(_ entries: [Entry]) -> [HerdProject] {
        var seen = Set<String>()
        var projects: [HerdProject] = []
        for entry in entries {
            guard let cwd = entry.report.cwd, seen.insert(cwd).inserted else { continue }
            projects.append(HerdProject(id: ProjectID(source: source, local: cwd), name: projectName(entry.report), path: cwd))
        }
        return projects
    }
}
