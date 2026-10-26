import Foundation
import Testing
@testable import ShepherdCore
@testable import ShepherdModules

@MainActor
final class StubContextReader: AgentContextReader {
    var reads: [String] = []
    var tokens = 184_213
    var finalMessage: String? = "Done."

    func read(_ session: AgentSession) async throws -> AgentSessionReading? {
        reads.append(session.id)
        return session.kind == "claude" ? AgentSessionReading(contextTokens: tokens, finalMessage: finalMessage) : nil
    }
}

@MainActor
@Suite struct ContextModuleTests {
    let presence = Presence()
    let reader = StubContextReader()
    let store = HerdStore()
    let source = StubSource("herdr")

    init() {
        store.add(source)
        store.start()
    }

    func agent(_ local: String, _ status: HerdStatus, kind: String = "claude") -> HerdAgent {
        HerdAgent(id: AgentID(source: "herdr", local: local), kind: kind, name: local, status: status,
                  session: AgentSession(kind: kind, id: "session-\(local)", cwd: "/tmp/project-1"))
    }

    func send(_ agents: [HerdAgent]) {
        source.send(SourceUpdate(agents: agents, state: .live))
    }

    func module() -> (ContextModule, ModuleContext) {
        let context = ModuleContext(store: store, presence: presence, actions: RecordingActions(), contextReader: reader)
        return (ContextModule(context: context), context)
    }

    /// Waits up to 3 s for `condition`, so a busy test run does not fail on timing.
    func until(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func settle() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    @Test func nothingIsReadWhileHidden() async {
        let (module, context) = module()
        send([agent("p1", .working)])
        await until { store.agents.count == 1 }
        send([agent("p1", .idle)])
        await settle()
        #expect(reader.reads.isEmpty)
        #expect(context.agentContext.tokens.isEmpty)
        _ = module
    }

    @Test func nothingIsReadOnTheGadgetsTab() async {
        let (module, _) = module()
        send([agent("p1", .working)])
        await until { store.agents.count == 1 }
        presence.setPanel("notch", showing: .gadgets)
        await settle()
        #expect(reader.reads.isEmpty)
        presence.setPanel("notch", showing: .agents)
        await until { reader.reads.count == 1 }
        #expect(reader.reads == ["session-p1"])
        _ = module
    }

    @Test func openingReadsEveryAgentWithASession() async {
        let (module, context) = module()
        let plain = HerdAgent(id: AgentID(source: "herdr", local: "p3"), kind: "claude", name: "p3", status: .idle)
        send([agent("p1", .working), agent("p2", .idle, kind: "codex"), plain])
        await until { store.agents.count == 3 }
        presence.setPanel("notch", showing: .agents)
        await until { reader.reads.count == 2 }
        await settle()
        #expect(reader.reads.sorted() == ["session-p1", "session-p2"])
        #expect(context.agentContext.tokens == [AgentID(source: "herdr", local: "p1"): 184_213])
        _ = module
    }

    @Test func aStatusChangeWhileOpenReadsThatAgentAgain() async {
        let (module, context) = module()
        send([agent("p1", .working), agent("p2", .idle)])
        await until { store.agents.count == 2 }
        presence.setPanel("notch", showing: .agents)
        await until { reader.reads.count == 2 }
        reader.tokens = 190_000
        reader.finalMessage = "All green."
        send([agent("p1", .idle), agent("p2", .idle)])
        await until { reader.reads.count == 3 }
        await settle()
        #expect(reader.reads.last == "session-p1")
        #expect(reader.reads.count == 3)
        #expect(context.agentContext.tokens[AgentID(source: "herdr", local: "p1")] == 190_000)
        #expect(context.agentContext.finalMessages[AgentID(source: "herdr", local: "p1")] == "All green.")
        #expect(context.agentContext.finalMessages[AgentID(source: "herdr", local: "p2")] == "Done.")
        _ = module
    }

    @Test func aGoneAgentLosesItsSize() async {
        let (module, context) = module()
        send([agent("p1", .idle)])
        await until { store.agents.count == 1 }
        presence.setPanel("menu", showing: .agents)
        await until { !context.agentContext.tokens.isEmpty }
        send([])
        await until { context.agentContext.tokens.isEmpty }
        #expect(context.agentContext.tokens.isEmpty)
        #expect(context.agentContext.finalMessages.isEmpty)
        _ = module
    }

    @Test func turningItOffClearsTheSizes() async {
        let context = ModuleContext(store: store, presence: presence, actions: RecordingActions(), contextReader: reader)
        var module: ContextModule? = ContextModule(context: context)
        send([agent("p1", .idle)])
        await until { store.agents.count == 1 }
        presence.setPanel("menu", showing: .agents)
        await until { !context.agentContext.tokens.isEmpty }
        #expect(module != nil)
        module = nil
        await until { context.agentContext.tokens.isEmpty }
        #expect(context.agentContext.tokens.isEmpty)
        #expect(context.agentContext.finalMessages.isEmpty)
    }

    @Test func rowsCarryTheSizeAndMessage() async {
        let context = ModuleContext(store: store, presence: presence, actions: RecordingActions(), contextReader: reader)
        let projects = ProjectsModule(context: context)
        let context2 = ContextModule(context: context)
        send([agent("p1", .idle)])
        await until { store.agents.count == 1 }
        presence.setPanel("menu", showing: .agents)
        await until { !context.agentContext.tokens.isEmpty }
        guard case .project(let card)? = projects.panel?.items.first else {
            Issue.record("no card")
            return
        }
        #expect(card.agents.first?.contextTokens == 184_213)
        #expect(card.agents.first?.finalMessage == "Done.")
        _ = context2
    }
}
