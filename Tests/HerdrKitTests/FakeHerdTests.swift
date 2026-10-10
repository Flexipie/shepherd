import HerdrFake
import Testing

/// The fake follows what herdr 0.9.3 was seen doing (see PRD "What herdr gives us").
@Suite struct FakeHerdTests {
    func seq(_ herd: FakeHerd, _ pane: String) -> UInt64? { herd.panes.first { $0.id == pane }?.stateChangeSeq }

    @Test func oneCounterForEveryAgent() {
        var herd = FakeHerd.basic
        herd.setStatus("w2:p2", "blocked")
        herd.setStatus("w1:p1", "blocked")
        #expect(seq(herd, "w2:p2") == 4)
        #expect(seq(herd, "w1:p1") == 5)
    }

    @Test func finishingUnseenIsDoneAndSeeingItClearsWithoutACount() {
        var herd = FakeHerd.basic
        herd.setStatus("w2:p2", "done")
        #expect(herd.status(of: "w2:p2") == "done")
        let finished = seq(herd, "w2:p2")
        #expect(herd.panes.first { $0.id == "w2:p2" }?.completionSeq == finished)
        #expect(herd.focus(workspace: "w2") == ["w2:p2"])
        #expect(herd.status(of: "w2:p2") == "idle")
        #expect(seq(herd, "w2:p2") == finished)
    }

    @Test func finishingWhileOnScreenIsIdleAtOnce() {
        var herd = FakeHerd.basic
        herd.focus(workspace: "w1")
        herd.setStatus("w1:p1", "done")
        #expect(herd.status(of: "w1:p1") == "idle")
    }
}
