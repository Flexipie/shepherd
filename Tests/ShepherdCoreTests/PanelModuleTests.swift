import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
@Suite struct PanelModuleTests {
    let store = HerdStore()
    let presence = Presence()
    let herdr = StubSource("herdr")
    let other = StubSource("other")
    let config: ConfigStore
    var context: ModuleContext { ModuleContext(store: store, presence: presence, actions: RecordingActions(), config: config) }

    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)

    init() {
        config = ConfigStore(fixed: .defaults)
        herdr.capabilities = [.focus, .focusProject]
        other.capabilities = []
        store.add(herdr)
        store.add(other)
    }

    func agentRows(_ section: PanelSection?) -> [PanelAgentRow] {
        section?.items.compactMap { if case .agent(let row) = $0 { row } else { nil } } ?? []
    }

    func cards(_ section: PanelSection?) -> [PanelProjectCard] {
        section?.items.compactMap { if case .project(let card) = $0 { card } else { nil } } ?? []
    }

    @Test func queueIsBlockedFirstThenLongestWaitingFromLiveSources() {
        store.apply(SourceUpdate(agents: [
            herdAgent("herdr", "a", .done, since: early),
            herdAgent("herdr", "b", .blocked, since: late),
            herdAgent("herdr", "c", .working),
            herdAgent("herdr", "d", .blocked, since: early, tokens: ["summary": "needs a yes"]),
        ], state: .live), from: "herdr")
        store.apply(SourceUpdate(agents: [herdAgent("other", "x", .blocked, since: early)],
                                 state: .stale("fell behind")), from: "other")
        let section = QueueModule(context: context).panel
        #expect(section?.title == "Needs you")
        let rows = agentRows(section)
        #expect(rows.map(\.agent.id.description) == ["herdr:d", "herdr:b", "herdr:a"])
        #expect(rows.map(\.action) == [.jump(rows[0].agent.id), .jump(rows[1].agent.id), .jump(rows[2].agent.id)])
        #expect(rows[0].tokens == [[StyledToken(name: "summary", text: "needs a yes")]])
    }

    @Test func emptyQueueSaysSo() {
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "a", .working)], state: .live), from: "herdr")
        let section = QueueModule(context: context).panel
        #expect(section?.items.isEmpty == true)
        #expect(section?.emptyText == "Nothing needs you")
    }

    @Test func projectCardsWithTokenLinesAndAgents() {
        let mine = TokenLayout(projects: [[TokenEntry(name: "pr", rules: [TokenRule(.contains("draft"), style: TokenStyle(dim: true))])]])
        let source = TokenLayout(projects: [[TokenEntry(name: "ignored")]], agents: [[TokenEntry(name: "summary", style: TokenStyle(bold: true))]])
        let config = ConfigStore(fixed: ShepherdConfig(tokens: mine))
        let context = ModuleContext(store: store, presence: presence, actions: RecordingActions(), config: config)
        store.apply(SourceUpdate(
            agents: [herdAgent("herdr", "a", .blocked, projectID: "w2", tokens: ["summary": "tests pass"]),
                     herdAgent("herdr", "b", .working, projectID: "w1")],
            projects: [herdProject("herdr", "w1", tokens: ["pr": "#3 draft", "ignored": "x"]), herdProject("herdr", "w2"),
                       herdProject("herdr", "empty")],
            state: .live, tokenLayout: source), from: "herdr")
        let cards = cards(ProjectsModule(context: context).panel)
        #expect(cards.map(\.project.name) == ["project w1", "project w2", "project empty"])
        #expect(cards[0].tokens == [[StyledToken(name: "pr", text: "#3 draft", dim: true)]])
        #expect(cards[0].agents.map(\.agent.id.local) == ["b"])
        #expect(cards[1].agents.first?.tokens == [[StyledToken(name: "summary", text: "tests pass", bold: true)]])
        #expect(cards[2].agents.isEmpty)
        #expect(cards[0].action == .focusProject(ProjectID(source: "herdr", local: "w1")))
        #expect(cards.allSatisfy { $0.isLive })
    }

    @Test func nonLiveSourcesAreDimmedAndCannotFocusWhatTheyCannot() {
        store.apply(SourceUpdate(agents: [herdAgent("other", "x", .blocked, projectID: "o1")],
                                 projects: [herdProject("other", "o1")], state: .disconnected("not running")), from: "other")
        let card = cards(ProjectsModule(context: context).panel).first
        #expect(card?.isLive == false)
        #expect(card?.agents.first?.isLive == false)
        #expect(card?.action == nil)
        #expect(card?.agents.first?.action == nil)
    }

    @Test func agentsWithoutAProjectGetASourceCard() {
        store.apply(SourceUpdate(agents: [HerdAgent(id: AgentID(source: "other", local: "z"), name: "z", status: .idle)],
                                 state: .live), from: "other")
        let cards = cards(ProjectsModule(context: context).panel)
        #expect(cards.map(\.project.name) == ["other"])
        #expect(cards.first?.agents.map(\.agent.id.local) == ["z"])
    }
}

@MainActor
@Suite struct ModuleRegistryTests {
    struct TimedOut: Error {}

    @Test func buildsFromConfigAndRebuildsOnChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "shepherd-registry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "config.json")
        let config = ConfigStore(url: url)
        defer { config.stop() }
        let store = HerdStore()
        let context = ModuleContext(store: store, presence: Presence(), actions: RecordingActions(), config: config)
        let registry = ModuleRegistry(available: BuiltinModules.all, context: context)
        #expect(registry.modules.map { type(of: $0).id } == ["status", "notch", "queue", "projects"])
        let notch = registry.modules[1]

        try Data(#"{"modules": ["projects", "notch", "nope", "queue", "nope2"]}"#.utf8).write(to: url, options: .atomic)
        for _ in 0..<300 where registry.modules.count != 3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(registry.modules.map { type(of: $0).id } == ["projects", "notch", "queue"])
        #expect(registry.modules[1] === notch, "a module that stays keeps its state")
        #expect(config.problems == [#"config: unknown module "nope", "nope2""#])

        try FileManager.default.removeItem(at: url)
        for _ in 0..<300 where registry.modules.count != 4 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(registry.modules.map { type(of: $0).id } == ["status", "notch", "queue", "projects"])
        #expect(config.problems.isEmpty)
    }
}
