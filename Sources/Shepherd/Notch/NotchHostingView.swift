import AppKit
import Observation
import ShepherdCore
import ShepherdUI
import SwiftUI

/// What the notch surface shows right now. The controller changes it, inside an animation when
/// the shape should morph.
@MainActor
@Observable
final class NotchSurfaceModel {
    var mode: NotchSurfaceMode?
    /// The expanded shape's height, notch included, as the panel last asked for it.
    var expandedHeight: CGFloat = 0
}

struct NotchSurfaceRoot: View {
    let model: NotchSurfaceModel
    let metrics: NotchMetrics
    let panelMaxHeight: CGFloat?
    let perform: (PanelAction) -> Void
    let onExpand: () -> Void
    let onExpandedHeight: (CGFloat) -> Void

    var body: some View {
        if let mode = model.mode {
            NotchSurfaceView(mode: mode, metrics: metrics, expandedHeight: model.expandedHeight, panelMaxHeight: panelMaxHeight,
                             perform: perform, onExpand: onExpand, onExpandedHeight: onExpandedHeight)
        }
    }
}

/// Hosts the surface across the whole canvas and reports the mouse entering and leaving
/// `hoverRect` (the current shape, in this view's coordinates). An AppKit tracking area rather
/// than a global mouse monitor, so nothing wakes while the mouse is elsewhere.
final class NotchHostingView: NSHostingView<NotchSurfaceRoot> {
    var onHover: ((Bool) -> Void)?
    var hoverRect: NSRect = .zero {
        didSet { if hoverRect != oldValue { updateTrackingAreas() } }
    }
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === hoverArea else { return super.mouseEntered(with: event) }
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === hoverArea else { return super.mouseExited(with: event) }
        onHover?(false)
    }

    /// A click on a non-key panel goes straight to the row under it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
