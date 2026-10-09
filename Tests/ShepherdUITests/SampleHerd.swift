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

    static func row(_ agent: HerdAgent, live: Bool = true) -> PanelAgentRow {
        let tokens = agent.tokens["summary"].map { [[StyledToken(name: "summary", text: $0, dim: agent.status == .done)]] } ?? []
        return PanelAgentRow(agent: agent, tokens: tokens, isLive: live, action: .jump(agent.id))
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
}
