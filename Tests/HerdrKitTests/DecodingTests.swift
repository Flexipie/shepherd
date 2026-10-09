import Foundation
import Testing
@testable import HerdrKit

@Suite struct DecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func snapshotWithEmptyFieldsLeftOut() throws {
        let snapshot = try decode(SessionSnapshot.self, """
        {"version":"0.9.3","protocol":22,"focused_pane_id":"w1:p1",
         "workspaces":[{"workspace_id":"w1","number":1,"label":"workspace 1","focused":true,"pane_count":1,
                        "tab_count":1,"active_tab_id":"w1:t1","agent_status":"blocked"}],
         "tabs":[{"tab_id":"w1:t1","workspace_id":"w1","number":1,"label":"tab","focused":true,"pane_count":1,
                  "agent_status":"blocked"}],
         "panes":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","terminal_id":"t1","focused":true,
                   "agent_status":"blocked","revision":3}],
         "layouts":[],
         "agents":[{"pane_id":"w1:p1","workspace_id":"w1","tab_id":"w1:t1","terminal_id":"t1","agent":"claude",
                    "agent_status":"blocked","state_change_seq":4,"completion_seq":null,"focused":true,"revision":3}]}
        """)
        #expect(snapshot.protocol == 22)
        #expect(snapshot.workspaces.first?.tokens == [:])
        let agent = try #require(snapshot.agents.first)
        #expect(agent.status == .blocked)
        #expect(agent.stateChangeSeq == 4)
        #expect(agent.completionSeq == nil)
        #expect(agent.displayName == "claude")
        #expect(agent.stateLabels.isEmpty)
    }

    @Test func unknownFieldsAndStatusesAreTolerated() throws {
        let agent = try decode(Agent.self, """
        {"pane_id":"w1:p1","workspace_id":"w1","agent_status":"pondering","brand_new_field":{"x":1},
         "display_agent":"Reviewer","state_labels":{"pondering":"thinking hard"},"tokens":{"pr":"12"}}
        """)
        #expect(agent.status == .unrecognized("pondering"))
        #expect(agent.displayName == "Reviewer")
        #expect(agent.statusLabel == "thinking hard")
        #expect(agent.tokens == ["pr": "12"])
        #expect(agent.stateChangeSeq == 0)
    }

    @Test func malformedArrayElementIsSkipped() throws {
        let snapshot = try decode(SessionSnapshot.self, """
        {"version":"x","protocol":22,"workspaces":[{"label":"no id"},{"workspace_id":"w2"}],
         "tabs":[],"panes":[],"agents":[]}
        """)
        #expect(snapshot.workspaces.map(\.id) == ["w2"])
    }

    @Test func eventNamesAreNormalised() throws {
        let global = try decode(HerdrEvent.self, #"{"event":"workspace_focused","data":{"type":"workspace_focused","workspace_id":"w1"}}"#)
        let pane = try decode(HerdrEvent.self, #"{"event":"pane.agent_status_changed","data":{"pane_id":"w1:p1","workspace_id":"w1","agent_status":"done"}}"#)
        #expect(global == HerdrEvent(kind: "workspace_focused", workspaceID: "w1"))
        #expect(pane.kind == "pane_agent_status_changed")
        #expect(pane.paneID == "w1:p1")
    }

    @Test func incomingLinesAreClassified() throws {
        guard case .result(let id, _) = try IncomingLine(Data(#"{"id":"r1","result":{"type":"pong"}}"#.utf8)) else {
            Issue.record("expected a result"); return
        }
        #expect(id == "r1")
        guard case .error(_, let code, _) = try IncomingLine(Data(#"{"id":"s1","error":{"code":"events_lost","message":"behind"}}"#.utf8)) else {
            Issue.record("expected an error"); return
        }
        #expect(code == .eventsLost)
        guard case .event(let event) = try IncomingLine(Data(#"{"event":"pane_created","data":{}}"#.utf8)) else {
            Issue.record("expected an event"); return
        }
        #expect(event.kind == "pane_created")
        #expect(throws: HerdrError.self) { try IncomingLine(Data("[1]".utf8)) }
    }

    @Test func subscriptionParamsNamePanesOnlyForStatusChanges() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(SubscriptionSet(paneIDs: ["w1:p2", "w1:p1"]).params), as: UTF8.self)
        #expect(json.contains(#"{"pane_id":"w1:p1","type":"pane.agent_status_changed"}"#))
        #expect(json.contains(#"{"type":"workspace.created"}"#))
        #expect(!json.contains("null"))
    }

    @Test func compatibility() {
        #expect(Compatibility(protocol: 22) == .matched)
        #expect(Compatibility(protocol: 21) == .older(21))
        #expect(Compatibility(protocol: 23) == .newer(23))
    }
}
