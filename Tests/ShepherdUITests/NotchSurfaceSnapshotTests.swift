import AppKit
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

/// The notch surface in each state, at fixed notch metrics: a 200 x 32 notch.
@MainActor
@Suite struct NotchSurfaceSnapshotTests {
    let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32, maxExpandedHeight: 720)

    func check(_ name: String, _ mode: NotchSurfaceMode, height: CGFloat, expandedHeight: CGFloat = 0,
               sourceLocation: SourceLocation = #_sourceLocation) throws {
        let canvas = metrics.canvas
        try Snapshot.check(name, width: canvas.width, sourceLocation: sourceLocation) {
            NotchSurfaceView(mode: mode, metrics: metrics, expandedHeight: expandedHeight, clock: .fixed(SampleHerd.now))
                // Only the top of the canvas, where the shape is.
                .frame(width: canvas.width, height: height, alignment: .top)
                .clipped()
        }
    }

    @Test func quietEar() throws {
        try check("notch-ear", .ear(StatusContribution(symbol: "pawprint", accessibilityLabel: "quiet")), height: 44)
    }

    @Test func attentionEar() throws {
        let status = StatusContribution(symbol: "pawprint.fill", count: 12, emphasis: .attention, accessibilityLabel: "12 waiting")
        try check("notch-ear-attention", .ear(status), height: 44)
    }

    @Test func notLiveEar() throws {
        let status = StatusContribution(symbol: "pawprint", emphasis: .dimmed, accessibilityLabel: "connecting")
        try check("notch-ear-dimmed", .ear(status), height: 44)
    }

    @Test func alert() throws {
        let item = NotchItem(agent: SampleHerd.blockedCodex, reason: .blocked, others: 2)
        try check("notch-alert", .alert(item), height: 32 + NotchPillView.contentHeight + 8)
    }

    @Test func expanded() throws {
        let panel = VStack(spacing: 0) {
            PanelView(content: SampleHerd.content, clock: .fixed(SampleHerd.now)) { _ in }.padding(.bottom, 4)
        }
        let height = NSHostingView(rootView: panel.environment(\.colorScheme, .dark)).fittingSize.height + 32
        try check("notch-expanded", .expanded(SampleHerd.content), height: height + 8, expandedHeight: height)
    }

    @Test func shapesStayInsideTheCanvas() {
        let canvas = metrics.canvas
        for kind in [NotchMetrics.Kind.ear, .alert, .expanded] {
            #expect(canvas.contains(metrics.outline(kind, expandedHeight: 10_000)))
        }
        // The ear and the alert both cover the notch.
        let notch = CGRect(x: 0, y: 0, width: 200, height: 32)
        #expect(metrics.body(.ear, expandedHeight: 0).contains(notch))
        #expect(metrics.body(.alert, expandedHeight: 0).contains(notch))
        #expect(metrics.body(.expanded, expandedHeight: 10_000).height == 720)
    }
}
