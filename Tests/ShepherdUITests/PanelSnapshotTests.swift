import Foundation
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

@MainActor
@Suite struct PanelSnapshotTests {
    @Test func queueRows() throws {
        try Snapshot.check("queue-row", width: 340) {
            VStack(spacing: 0) {
                AgentRow(row: SampleHerd.row(SampleHerd.blockedCodex), now: SampleHerd.now, showsProject: true, isSelected: true)
                AgentRow(row: SampleHerd.row(SampleHerd.finished), now: SampleHerd.now, showsProject: true)
            }
            .padding(8)
        }
    }

    /// In the notch bar a selected row shows the jump arrow; unselected rows keep its room.
    @Test func queueRowsWithJump() throws {
        try Snapshot.check("queue-row-jump", width: 340) {
            VStack(spacing: 0) {
                AgentRow(row: SampleHerd.row(SampleHerd.blockedCodex), now: SampleHerd.now, showsProject: true, isSelected: true,
                         onJump: {})
                AgentRow(row: SampleHerd.row(SampleHerd.finished), now: SampleHerd.now, showsProject: true, onJump: {})
            }
            .padding(8)
        }
    }

    @Test func projectCard() throws {
        try Snapshot.check("project-card", width: 340) {
            ProjectCard(card: SampleHerd.webCard, now: SampleHerd.now, selection: nil, sectionID: "projects",
                        perform: { _ in }, hover: { _ in })
                .padding(8)
        }
    }

    @Test func staleProjectCard() throws {
        try Snapshot.check("project-card-stale", width: 340) {
            ProjectCard(card: SampleHerd.card(SampleHerd.api, [SampleHerd.blockedCodex], live: false), now: SampleHerd.now,
                        selection: nil, sectionID: "projects", perform: { _ in }, hover: { _ in })
                .padding(8)
        }
    }

    @Test func wholePanel() throws {
        try Snapshot.check("panel", width: PanelView.width) {
            PanelView(content: SampleHerd.content, clock: .fixed(SampleHerd.now),
                      selection: PanelTarget.all(in: SampleHerd.content.sections).first?.id) { _ in }
        }
    }

    @Test func emptyAndDisconnectedPanel() throws {
        try Snapshot.check("panel-disconnected", width: PanelView.width) {
            PanelView(content: SampleHerd.disconnected, clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    @Test func notchPill() throws {
        let item = NotchItem(agent: SampleHerd.blockedCodex, reason: .blocked, others: 2)
        try Snapshot.check("notch-pill-floating", width: 340) {
            NotchPillView(item: item) {}.frame(height: NotchPillView.contentHeight).padding(6)
        }
    }
}

@Suite struct PanelNavigationTests {
    @Test func targetsRunTopToBottomAndKeepSectionsApart() {
        let targets = PanelTarget.all(in: SampleHerd.content.sections)
        #expect(targets.count == 3 + 3 + 5)
        #expect(targets.first?.action == .jump(SampleHerd.blockedCodex.id))
        #expect(targets[3].action == .focusProject(SampleHerd.api.id))
        // The same agent in the queue and in its card are two targets.
        #expect(Set(targets.map(\.id)).count == targets.count)
    }

    @Test func movingClampsAtTheEnds() {
        let targets = PanelTarget.all(in: SampleHerd.content.sections)
        #expect(PanelTarget.move(from: nil, by: 1, in: targets) == targets.first?.id)
        #expect(PanelTarget.move(from: nil, by: -1, in: targets) == targets.last?.id)
        #expect(PanelTarget.move(from: targets[0].id, by: -1, in: targets) == targets[0].id)
        #expect(PanelTarget.move(from: targets[0].id, by: 1, in: targets) == targets[1].id)
        #expect(PanelTarget.move(from: targets.last?.id, by: 1, in: targets) == targets.last?.id)
        #expect(PanelTarget.move(from: "gone", by: 1, in: []) == nil)
    }
}

@Suite struct BarChoiceTests {
    let agent = SampleHerd.blockedCodex.id

    @Test func returnOpensTheStageAndCommandReturnJumps() {
        #expect(BarChoice.choose(.jump(agent), command: false, hasStage: true) == .openStage(agent))
        #expect(BarChoice.choose(.jump(agent), command: true, hasStage: true) == .perform(.jump(agent)))
    }

    @Test func withoutAStageEverythingPerforms() {
        #expect(BarChoice.choose(.jump(agent), command: false, hasStage: false) == .perform(.jump(agent)))
    }

    @Test func projectHeadersAlwaysPerform() {
        let focus = PanelAction.focusProject(SampleHerd.api.id)
        #expect(BarChoice.choose(focus, command: false, hasStage: true) == .perform(focus))
        #expect(BarChoice.choose(focus, command: true, hasStage: true) == .perform(focus))
    }
}

@Suite struct BarNavigationTests {
    let columns = BarColumn.layout(SampleHerd.content.sections)
    var targets: [PanelTarget] { PanelTarget.all(in: columns) }

    func target(_ column: Int, _ row: Int) -> PanelTarget.ID {
        targets.first { $0.column == column && $0.row == row }!.id
    }

    @Test func queueIsPinnedFirstAndEachCardIsAColumn() {
        #expect(columns.map(\.id) == ["queue", "projects/herdr:w1", "projects/herdr:w2", "projects/herdr:w3"])
        #expect(columns[0].isQueue)
        #expect(columns.dropFirst().allSatisfy { $0.isCard })
        // Config order does not move the queue off the left.
        let reordered = BarColumn.layout(SampleHerd.content.sections.reversed())
        #expect(reordered.first?.isQueue == true)
        // Any other section is one column, so a new module's section just appears.
        let other = PanelSection(id: "other", title: "Other", items: [.notice("hello")], emptyText: "")
        #expect(BarColumn.layout([other]).map(\.id) == ["other"])
        // An empty projects section is one column, to show its empty text.
        #expect(BarColumn.layout(SampleHerd.disconnected.sections).map(\.id) == ["queue", "projects"])
    }

    @Test func targetsAreLaidOutByColumn() {
        // Queue: three agents. Cards: header plus agents (2, 2, 1).
        #expect(targets.map(\.column) == [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3])
        #expect(targets.map(\.row) == [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1])
        #expect(Set(targets.map(\.id)) == Set(PanelTarget.all(in: SampleHerd.content.sections).map(\.id)))
    }

    @Test func upAndDownStayInTheColumn() {
        #expect(PanelTarget.move(from: target(1, 0), .down, in: targets) == target(1, 1))
        #expect(PanelTarget.move(from: target(1, 2), .down, in: targets) == target(1, 2))
        #expect(PanelTarget.move(from: target(1, 0), .up, in: targets) == target(1, 0))
    }

    @Test func leftAndRightGoToTheNearestRow() {
        #expect(PanelTarget.move(from: target(0, 2), .right, in: targets) == target(1, 2))
        #expect(PanelTarget.move(from: target(2, 2), .right, in: targets) == target(3, 1))
        #expect(PanelTarget.move(from: target(3, 1), .right, in: targets) == target(3, 1))
        #expect(PanelTarget.move(from: target(1, 1), .left, in: targets) == target(0, 1))
        #expect(PanelTarget.move(from: target(0, 0), .left, in: targets) == target(0, 0))
    }

    @Test func emptyColumnsAreSkipped() {
        let empty = PanelSection(id: "middle", title: "Middle", items: [], emptyText: "nothing")
        let columns = BarColumn.layout([SampleHerd.queue, empty, SampleHerd.projects])
        let targets = PanelTarget.all(in: columns)
        let firstCard = targets.first { $0.column == 2 }!.id
        #expect(PanelTarget.move(from: targets[0].id, .right, in: targets) == firstCard)
        #expect(PanelTarget.move(from: firstCard, .left, in: targets) == targets[0].id)
    }

    @Test func withNothingSelected() {
        #expect(PanelTarget.move(from: nil, .down, in: targets) == targets.first?.id)
        #expect(PanelTarget.move(from: nil, .right, in: targets) == targets.first?.id)
        #expect(PanelTarget.move(from: nil, .up, in: targets) == targets.last?.id)
        #expect(PanelTarget.move(from: nil, .left, in: targets) == targets.last?.id)
        #expect(PanelTarget.move(from: "gone", .down, in: []) == nil)
    }
}
