import Foundation
import Testing
@testable import ShepherdCore

@MainActor
@Suite struct HerdStoreTests {
    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)

    @Test func mergesSourcesAndOrdersNeedsYouAcrossThem() {
        let store = HerdStore()
        let herdr = StubSource("herdr")
        let other = StubSource("other")
        store.add(herdr)
        store.add(other)
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "a", .done, since: early), herdAgent("herdr", "b", .working)],
                                 state: .live), from: "herdr")
        store.apply(SourceUpdate(agents: [herdAgent("other", "a", .blocked, since: late), herdAgent("other", "c", .done, since: late)],
                                 state: .live), from: "other")
        #expect(store.agents.map(\.id.description) == ["herdr:a", "herdr:b", "other:a", "other:c"])
        #expect(store.needsYou.map(\.id.description) == ["other:a", "herdr:a", "other:c"])
        #expect(store.workingCount == 1)
        #expect(store.overallState == .live)
    }

    @Test func mergesProjectsInSourceOrder() {
        let store = HerdStore()
        store.add(StubSource("herdr"))
        store.add(StubSource("other"))
        store.apply(SourceUpdate(agents: [herdAgent("other", "a", .working, projectID: "x")],
                                 projects: [herdProject("other", "x")], state: .live), from: "other")
        store.apply(SourceUpdate(agents: [herdAgent("herdr", "a", .working, projectID: "w2"), herdAgent("herdr", "b", .done, projectID: "w1")],
                                 projects: [herdProject("herdr", "w2"), herdProject("herdr", "w1"), herdProject("herdr", "empty")],
                                 state: .live), from: "herdr")
        #expect(store.projects.map(\.id.description) == ["herdr:w2", "herdr:w1", "herdr:empty", "other:x"])
        #expect(store.agents(in: ProjectID(source: "herdr", local: "w1")).map(\.id.local) == ["b"])
        #expect(store.agents(in: ProjectID(source: "herdr", local: "empty")).isEmpty)
        #expect(store.agents(in: ProjectID(source: "other", local: "x")).map(\.id.description) == ["other:a"])
    }

    @Test func focusProjectRespectsCapabilities() async throws {
        let store = HerdStore()
        let herdr = StubSource("herdr")
        herdr.capabilities = [.focus, .focusProject]
        let other = StubSource("other")
        store.add(herdr)
        store.add(other)
        try await store.focusProject(ProjectID(source: "herdr", local: "w1"))
        #expect(herdr.focusedProjects == [ProjectID(source: "herdr", local: "w1")])
        await #expect(throws: AgentSourceError.unsupported(.focusProject)) {
            try await store.focusProject(ProjectID(source: "other", local: "x"))
        }
        await #expect(throws: AgentSourceError.unknownSource("nope")) {
            try await store.focusProject(ProjectID(source: "nope", local: "x"))
        }
    }

    @Test func overallStateReportsTheFirstProblem() {
        let store = HerdStore()
        store.add(StubSource("herdr"))
        store.add(StubSource("other"))
        #expect(store.overallState == .connecting)
        store.apply(SourceUpdate(agents: [], state: .live), from: "herdr")
        store.apply(SourceUpdate(agents: [], state: .disconnected("not running")), from: "other")
        #expect(store.overallState == .disconnected("not running"))
    }

    @Test func focusGoesToTheOwningSourceAndRespectsCapabilities() async throws {
        let store = HerdStore()
        let herdr = StubSource("herdr")
        let other = StubSource("other")
        other.capabilities = []
        store.add(herdr)
        store.add(other)
        try await store.focus(AgentID(source: "herdr", local: "a"))
        #expect(herdr.focused == [AgentID(source: "herdr", local: "a")])
        await #expect(throws: AgentSourceError.unsupported(.focus)) { try await store.focus(AgentID(source: "other", local: "a")) }
        await #expect(throws: AgentSourceError.unknownSource("nope")) { try await store.focus(AgentID(source: "nope", local: "a")) }
    }

    @Test func updatesFlowFromStartedSources() async throws {
        let store = HerdStore()
        let herdr = StubSource("herdr")
        store.add(herdr)
        store.start()
        herdr.send(SourceUpdate(agents: [herdAgent("herdr", "a", .blocked)], state: .live))
        for _ in 0..<100 where store.needsYou.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.needsYou.map(\.id.local) == ["a"])
        await store.stop()
    }

    @Test func transitionsAreLogged() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "shepherd-log-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = TransitionLog(url: url)
        let store = HerdStore(log: log)
        store.add(StubSource("herdr"))
        let transition = HerdTransition(agent: AgentID(source: "herdr", local: "a"), kind: "claude", project: "project 1",
                                        from: .working, to: .done, at: late, marker: "t1|4")
        store.apply(SourceUpdate(agents: [], state: .live, transitions: [transition]), from: "herdr")
        #expect(store.lastTransitions == [transition])
        for _ in 0..<100 where await log.load().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await log.load() == [transition])
    }
}
