import AppKit
import ShepherdUI
import Testing
@testable import Shepherd

@MainActor
@Suite struct NotchPanelTests {
    /// The open bar at a measured height that is not whole points, on a 1512 x 982 screen with a
    /// 185-point notch (issue #124). The canvas, and so the shape's flat top, stays flush with the
    /// top of the screen, and the window covers the whole outline.
    @Test func fractionalBarStaysFlushWithTheTop() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32, maxExpandedHeight: 982 * 0.3, maxExpandedWidth: 1012)
        let geometry = NotchGeometry(metrics: metrics, notchOrigin: NSPoint(x: 663, y: 982), floatingFrame: .zero)
        let canvas = geometry.screenRect(metrics.canvas)
        let outline = geometry.screenRect(metrics.outline(.expanded, expandedHeight: 264.5))
        let panel = NotchSurfacePanel()
        let view = NSView(frame: NSRect(origin: .zero, size: canvas.size))
        panel.contentView = NSView()
        panel.contentView?.addSubview(view)

        panel.setFrame(outline, keeping: view, at: canvas)

        let placed = panel.convertToScreen(view.frame)
        #expect(abs(placed.maxY - 982) < 0.01)
        #expect(abs(placed.minX - canvas.minX) < 0.01)
        #expect(panel.frame.contains(outline))
    }
}
