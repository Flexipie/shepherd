import Foundation
import ShepherdCore
import ShepherdUI

/// A made-up herd for snapshots: five agents over three projects, two blocked, one finished,
/// tokens styled with rules. No real names, paths or ids.
enum SampleHerd {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func ago(_ minutes: Double, _ precision: Since.Precision = .exact) -> Since {
        Since(now.addingTimeInterval(-minutes * 60), precision)
    }

    static let api = HerdProject(id: ProjectID(source: "herdr", local: "w1"), name: "api", tokens: ["pr": "#142 draft", "ticket_state": "In Review"],
                                 isFocusedInSource: true)
    static let web = HerdProject(id: ProjectID(source: "herdr", local: "w2"), name: "web", tokens: ["pr": "#87", "review": "blocking: 2"])
    static let docs = HerdProject(id: ProjectID(source: "herdr", local: "w3"), name: "docs")

    static func agent(_ local: String, _ kind: String, _ project: HerdProject, _ status: HerdStatus, _ since: Since?,
                      label: String? = nil, tokens: [String: String] = [:]) -> HerdAgent {
        HerdAgent(id: AgentID(source: "herdr", local: local), kind: kind, name: kind, projectID: project.id, project: project.name,
                  status: status, statusLabel: label, since: since, tokens: tokens)
    }

    static let blockedCodex = agent("w1:p1", "codex", api, .blocked, ago(12), tokens: ["summary": "approve migration?"])
    static let blockedClaude = agent("w2:p1", "claude", web, .blocked, ago(4))
    static let finished = agent("w2:p2", "claude", web, .done, ago(95, .noLaterThan), tokens: ["summary": "tests pass"])
    static let working = agent("w1:p2", "claude", api, .working, ago(23))
    static let idle = agent("w3:p1", "pi", docs, .idle, ago(240, .noLaterThan))

    static let purple = HexColor("#cba6f7")!
    static let teal = HexColor("#94e2d5")!
    static let red = HexColor("#f38ba8")!

    static func row(_ agent: HerdAgent, live: Bool = true, context: Int? = nil) -> PanelAgentRow {
        let tokens = agent.tokens["summary"].map { [[StyledToken(name: "summary", text: $0, dim: agent.status == .done)]] } ?? []
        return PanelAgentRow(agent: agent, tokens: tokens, isLive: live, action: .jump(agent.id), contextTokens: context)
    }

    static let queue = PanelSection(id: "queue", title: "Needs you",
                                    items: [blockedCodex, blockedClaude, finished].map { .agent(row($0)) },
                                    emptyText: "Nothing needs you")

    static func card(_ project: HerdProject, _ agents: [HerdAgent], tokens: [[StyledToken]] = [], live: Bool = true) -> PanelProjectCard {
        PanelProjectCard(project: project, tokens: tokens, agents: agents.map { row($0, live: live) }, isLive: live,
                         action: .focusProject(project.id))
    }

    static let apiCard = card(api, [blockedCodex, working], tokens: [[
        StyledToken(name: "pr", text: "#142 draft", fg: teal, dim: true),
        StyledToken(name: "ticket_state", text: "In Review", fg: purple),
    ]])
    static let webCard = card(web, [blockedClaude, finished], tokens: [
        [StyledToken(name: "pr", text: "#87", fg: teal)],
        [StyledToken(name: "review", text: "blocking: 2", fg: red, bold: true)],
    ])
    static let docsCard = card(docs, [idle])

    static let projects = PanelSection(id: "projects", title: "Projects",
                                       items: [apiCard, webCard, docsCard].map(PanelItem.project), emptyText: "No projects")

    static let content = PanelContent(sections: [queue, projects], statusLines: ["2 working, 3 waiting", "herdr 0.9.3"])

    static let disconnected = PanelContent(
        sections: [PanelSection(id: "queue", title: "Needs you", items: [], emptyText: "Nothing needs you"),
                   PanelSection(id: "projects", title: "Projects", items: [], emptyText: "No projects")],
        statusLines: ["Not connected: herdr is not running. Retrying.", "herdr socket: ~/.config/herdr/herdr.sock"],
        problems: ["config: tokens.projects[0][0].fg: must be #RGB or #RRGGBB"])

    /// Twelve projects, one agent each, after the usual queue.
    static let manyProjects: PanelContent = {
        let cards = (1...12).map { index in
            let project = HerdProject(id: ProjectID(source: "herdr", local: "m\(index)"), name: "project \(index)")
            let status: HerdStatus = index.isMultiple(of: 3) ? .working : .idle
            return PanelItem.project(card(project, [agent("m\(index):p1", "claude", project, status, ago(Double(index * 7)))]))
        }
        let projects = PanelSection(id: "projects", title: "Projects", items: cards, emptyText: "No projects")
        return PanelContent(sections: [queue, projects], statusLines: ["4 working, 3 waiting"])
    }()

    // MARK: Usage

    static func meter(_ id: String, _ label: String, _ fraction: Double, _ text: String? = nil, resetsIn: TimeInterval? = nil) -> UsageMeter {
        UsageMeter(id: id, label: label, fraction: fraction, valueText: text ?? "\(Int(fraction * 100))%",
                   resetsAt: resetsIn.map { now.addingTimeInterval($0) })
    }

    static let personal = UsageProvider(id: "claude", name: "Claude, personal", plan: "Max 5x", meters: [
        meter("session", "Session", 0.77, resetsIn: 3 * 3600 + 37 * 60),
        meter("weekly", "Weekly", 0.21, resetsIn: 6 * 86_400 + 12 * 3600),
        meter("sonnet", "Sonnet", 0.03),
    ], notes: ["1 limit reset available"])

    static let team = UsageProvider(id: "claude@a1", name: "Claude, team", plan: "Team", isStale: true, meters: [
        meter("weekly", "Weekly", 1, resetsIn: 18 * 3600),
        meter("extraUsage", "Extra usage", 0.33, "$114 of $350"),
    ], notes: ["Session expired. Run `claude` to log in again."])

    static let codex = UsageProvider(id: "codex", name: "Codex", plan: "Plus", meters: [
        meter("weekly", "Weekly", 0.36, resetsIn: 5 * 86_400 + 8 * 3600),
    ])

    static let usage = PanelSection(id: "usage", title: "Usage", items: [.usage(personal), .usage(team), .usage(codex)],
                                    emptyText: "Reading usage…", tab: .gadgets)

    static let usageNotRunning = PanelSection(id: "usage", title: "Usage", items: [
        .notice("OpenUsage is not running. Shepherd reads Claude and Codex usage from it: github.com/robinebers/openusage"),
    ], emptyText: "", tab: .gadgets)

    // MARK: This Mac

    static let system = PanelSection(id: "system", title: "This Mac", items: [
        .usage(UsageProvider(id: "system", name: "CPU and memory", meters: [
            meter("cpu", "CPU", 0.23),
            meter("memory", "Memory", 0.86, "31.0 of 36 GB"),
        ])),
    ], emptyText: "Measuring…", tab: .gadgets)

    /// Every module on, in default order: the Agents and Gadgets tabs.
    static let contentWithGadgets = PanelContent(sections: [queue, usage, system, projects], statusLines: content.statusLines)
}

