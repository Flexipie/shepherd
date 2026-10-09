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
        let content = PanelContent(
            sections: [PanelSection(id: "queue", title: "Needs you", items: [], emptyText: "Nothing needs you"),
                       PanelSection(id: "projects", title: "Projects", items: [], emptyText: "No projects")],
            statusLines: ["Not connected: herdr is not running. Retrying.", "herdr socket: ~/.config/herdr/herdr.sock"],
            problems: ["config: tokens.projects[0][0].fg: must be #RGB or #RRGGBB"])
        try Snapshot.check("panel-disconnected", width: PanelView.width) {
            PanelView(content: content, clock: .fixed(SampleHerd.now)) { _ in }
        }
    }

    @Test func notchPill() throws {
        let item = NotchItem(agent: SampleHerd.blockedCodex, reason: .blocked, others: 2)
        try Snapshot.check("notch-pill", width: 360) {
            NotchPillView(item: item, style: .notch(height: 32)) {}.frame(height: 32 + NotchPillView.contentHeight)
        }
        try Snapshot.check("notch-pill-floating", width: 340) {
            NotchPillView(item: item, style: .floating) {}.frame(height: NotchPillView.contentHeight).padding(6)
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
