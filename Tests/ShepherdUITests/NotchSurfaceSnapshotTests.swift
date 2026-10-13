import AppKit
import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

/// The notch surface in each state, at fixed notch metrics: a 200 x 32 notch and a bar up to
/// 1000 x 300.
@MainActor
@Suite struct NotchSurfaceSnapshotTests {
    let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32, maxExpandedHeight: 300, maxExpandedWidth: 1000)

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

    /// The bar at its natural height, as the app sizes it.
    func checkExpanded(_ name: String, _ content: PanelContent, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let width = metrics.body(.expanded, expandedHeight: 0).width
        let bar = NotchBarView(content: content, clock: .fixed(SampleHerd.now), width: width) { _ in }
        let height = NSHostingView(rootView: bar.environment(\.colorScheme, .dark)).fittingSize.height + 32
        try check(name, .expanded(content), height: height + 8, expandedHeight: height, sourceLocation: sourceLocation)
    }

    @Test func expanded() throws {
        try checkExpanded("notch-expanded", SampleHerd.content)
    }

    @Test func expandedEmptyAndDisconnected() throws {
        try checkExpanded("notch-bar-disconnected", SampleHerd.disconnected)
    }

    /// More projects than fit: the columns past the right edge are cut off (in the app, they
    /// scroll sideways).
    @Test func expandedWithManyProjects() throws {
        try checkExpanded("notch-bar-many", SampleHerd.manyProjects)
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
        #expect(metrics.body(.expanded, expandedHeight: 10_000).height == 300)
        #expect(metrics.body(.expanded, expandedHeight: 0).width == 1000)
        // Never narrower than the notch with an ear on each side.
        let narrow = NotchMetrics(notchWidth: 200, notchHeight: 32, maxExpandedHeight: 300, maxExpandedWidth: 100)
        #expect(narrow.body(.expanded, expandedHeight: 0).width == 200 + 2 * NotchMetrics.earWidth)
    }
}
