import CoreGraphics

/// Where the notch surface's black shape sits in each state, so the app's window and the views
/// agree. Coordinates are relative to the notch: x from its left edge, y down from the top of the
/// screen. A body is the shape without its flared top corners; `outline` adds them.
public struct NotchMetrics: Equatable, Sendable {
    public enum Kind: Sendable, Hashable {
        /// The paw beside the notch.
        case ear
        /// The needs-you pill below the notch.
        case alert
        /// The panel, grown out of the notch.
        case expanded
    }

    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    /// The tallest the expanded shape may grow, notch included.
    public let maxExpandedHeight: CGFloat

    /// How far the ear sticks out to the left of the notch.
    public static let earWidth: CGFloat = 40
    /// How far the concave top corners reach into the menu bar on each side.
    public static let flare: CGFloat = 6
    static let alertMinWidth: CGFloat = 340
    static let expandedMinWidth: CGFloat = 380

    public init(notchWidth: CGFloat, notchHeight: CGFloat, maxExpandedHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.maxExpandedHeight = max(maxExpandedHeight, notchHeight + NotchPillView.contentHeight)
    }

    /// The shape's body for `kind`. `expandedHeight` (notch included) is clamped to the maximum.
    public func body(_ kind: Kind, expandedHeight: CGFloat) -> CGRect {
        switch kind {
        case .ear:
            return CGRect(x: -Self.earWidth, y: 0, width: Self.earWidth + notchWidth, height: notchHeight)
        case .alert:
            return centred(width: max(Self.alertMinWidth, notchWidth + 120), height: notchHeight + NotchPillView.contentHeight)
        case .expanded:
            let height = min(max(expandedHeight, notchHeight + NotchPillView.contentHeight), maxExpandedHeight)
            return centred(width: max(Self.expandedMinWidth, notchWidth + 2 * Self.earWidth), height: height)
        }
    }

    /// The body with its flared top corners: what a window must cover to show it whole.
    public func outline(_ kind: Kind, expandedHeight: CGFloat) -> CGRect {
        body(kind, expandedHeight: expandedHeight).insetBy(dx: -Self.flare, dy: 0)
    }

    /// Covers every state at its largest. The views draw in this space, so it stays put while the
    /// shape morphs.
    public var canvas: CGRect {
        [Kind.ear, .alert, .expanded]
            .map { outline($0, expandedHeight: maxExpandedHeight) }
            .reduce(CGRect.null) { $0.union($1) }
    }

    public func bottomRadius(_ kind: Kind) -> CGFloat {
        switch kind {
        case .ear: 10
        case .alert: 18
        case .expanded: 22
        }
    }

    private func centred(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: (notchWidth - width) / 2, y: 0, width: width, height: height)
    }
}
