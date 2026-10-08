import Foundation
import HerdrFake
import Testing
@testable import HerdrKit

@Suite struct SanitiserTests {
    let personal = """
    {"version":"0.9.3","protocol":22,"focused_pane_id":"real-pane-7",
     "workspaces":[{"workspace_id":"real-ws-1","label":"acme-billing CORE-1234","tokens":{"ticket":"CORE-1234 Fix invoices"}}],
     "panes":[{"pane_id":"real-pane-7","workspace_id":"real-ws-1","cwd":"/Users/jane/work/acme","agent_status":"blocked",
               "terminal_title":"claude: refactor acme payments","brand_new":{"secret_note":"jane's laptop"}}],
     "agents":[{"pane_id":"real-pane-7","workspace_id":"real-ws-1","agent":"claude","agent_status":"blocked",
                "name":"jane-reviewer","state_labels":{"blocked":"waiting for Jane"},"state_change_seq":4,
                "agent_session":{"agent":"claude","kind":"id","value":"0b9f7a1c-session"}}]}
    """

    @Test func noUserStringSurvives() throws {
        let input = try JSONSerialization.jsonObject(with: Data(personal.utf8))
        var sanitiser = Sanitiser()
        let output = sanitiser.sanitise(input)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
        for secret in ["real-ws-1", "real-pane-7", "acme", "CORE-1234", "jane", "Jane", "/Users", "0b9f7a1c", "laptop"] {
            #expect(!text.contains(secret), "\(secret) leaked")
        }
        for vocabulary in ["blocked", "claude", "0.9.3", "\"ticket\""] {
            #expect(text.contains(vocabulary), "\(vocabulary) was scrubbed")
        }
    }

    @Test func idsStayConsistentAndStillDecode() throws {
        let input = try JSONSerialization.jsonObject(with: Data(personal.utf8))
        var sanitiser = Sanitiser()
        let output = try JSONSerialization.data(withJSONObject: sanitiser.sanitise(input))
        let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: output)
        let agent = try #require(snapshot.agents.first)
        #expect(agent.id == snapshot.panes.first?.id)
        #expect(agent.id == snapshot.focusedPaneID)
        #expect(agent.workspaceID == snapshot.workspaces.first?.id)
        #expect(agent.stateChangeSeq == 4)
        #expect(agent.status == .blocked)
    }

    @Test func fakeServesARecordedFixture() async throws {
        let input = try JSONSerialization.jsonObject(with: Data(personal.utf8))
        var sanitiser = Sanitiser()
        let fixture = RecordedFixture(snapshot: try JSONSerialization.data(withJSONObject: sanitiser.sanitise(input)), events: [])
        let fake = FakeHerdrServer()
        await fake.serve(try RecordedFixture.decode(fixture.encoded()))
        try await fake.start()
        defer { Task { await fake.stop() } }
        let snapshot = try await HerdrClient(socketPath: fake.path).snapshot()
        #expect(snapshot.agents.map(\.status) == [.blocked])
    }

    @Test func recordedFixtureDrivesTheEngine() async throws {
        let fixture = try RecordedFixture.named("basic")
        let expected = try JSONDecoder().decode(SessionSnapshot.self, from: fixture.snapshot)
        #expect(!expected.agents.isEmpty)
        let fake = FakeHerdrServer()
        await fake.serve(fixture)
        try await fake.start()
        let engine = SessionEngine(client: HerdrClient(socketPath: fake.path), debounce: .milliseconds(10))
        let log = UpdateLog.recording(engine)
        await engine.start()
        let live = try await withTimeout { try await log.wait { $0.connection == .live } }
        #expect(live.session.agents.count == expected.agents.count)
        try await withTimeout { await fake.wait(for: .subscribers(1)) }
        await engine.stop()
        await fake.stop()
    }
}
