import ShepherdCore
import SwiftUI

/// What the notch surface shows. One black shape morphs between them.
public enum NotchSurfaceMode: Sendable, Equatable {
    /// Quiet: the paw beside the notch, orange with a count when agents need you.
    case ear(StatusContribution)
    /// Someone is blocked or just finished: the pill below the notch.
    case alert(NotchItem)
    /// Hovered: the panel.
    case expanded(PanelContent)

    public var kind: NotchMetrics.Kind {
        switch self {
        case .ear: .ear
        case .alert: .alert
        case .expanded: .expanded
        }
    }
}

/// The notch surface, drawn across `metrics.canvas`: a black shape sized for the mode, with the
/// mode's content below (or, for the ear, beside) the camera. Changing the mode inside an
/// animation morphs the shape and crossfades the content. Black whatever the appearance, so the
/// text is always light.
public struct NotchSurfaceView: View {
    let mode: NotchSurfaceMode
    let metrics: NotchMetrics
    let expandedHeight: CGFloat
    let clock: PanelClock
    let panelMaxHeight: CGFloat?
    let perform: (PanelAction) -> Void
    let onExpand: () -> Void
    let onExpandedHeight: (CGFloat) -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `expandedHeight` is the expanded shape's height, notch included; the view reports the
    /// height its panel wants through `onExpandedHeight`. `panelMaxHeight` makes the panel's
    /// sections scroll past that height.
    public init(mode: NotchSurfaceMode, metrics: NotchMetrics, expandedHeight: CGFloat, clock: PanelClock = .live,
                panelMaxHeight: CGFloat? = nil, perform: @escaping (PanelAction) -> Void = { _ in },
                onExpand: @escaping () -> Void = {}, onExpandedHeight: @escaping (CGFloat) -> Void = { _ in }) {
        self.mode = mode
        self.metrics = metrics
        self.expandedHeight = expandedHeight
        self.clock = clock
        self.panelMaxHeight = panelMaxHeight
        self.perform = perform
        self.onExpand = onExpand
        self.onExpandedHeight = onExpandedHeight
    }

    public var body: some View {
        let canvas = metrics.canvas
        let body = metrics.body(mode.kind, expandedHeight: expandedHeight).offsetBy(dx: -canvas.minX, dy: 0)
        let notch = NotchShape(frame: body, radius: metrics.bottomRadius(mode.kind))
        // With Reduce Motion the shape changes at once and only the content crossfades.
        let shape = reduceMotion ? AnyShape(Unanimated(shape: notch)) : AnyShape(notch)
        ZStack(alignment: .topLeading) {
            shape.fill(Color.black)
            content
                .id(mode.kind)
                .transition(.opacity)
                .frame(width: body.width, height: body.height, alignment: .top)
                .offset(x: body.minX, y: body.minY)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .ear(let status): ear(status)
        case .alert(let item): alert(item)
        case .expanded(let content): expanded(content)
        }
    }

    private func ear(_ status: StatusContribution) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .semibold))
            if let count = status.count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(earColor(status.emphasis))
        .frame(width: NotchMetrics.earWidth, height: metrics.notchHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityHint("Opens the panel")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onExpand)
    }

    private func earColor(_ emphasis: StatusContribution.Emphasis) -> Color {
        switch emphasis {
        case .normal: Color.white.opacity(0.85)
        case .attention: Color.orange
        case .dimmed: Color.white.opacity(0.35)
        }
    }

    private func alert(_ item: NotchItem) -> some View {
        Button {
            perform(.jump(item.agent.id))
        } label: {
            VStack(spacing: 0) {
                Color.clear.frame(height: metrics.notchHeight)
                NotchPillRow(item: item, primary: .white, secondary: Color.white.opacity(0.65), hovering: hovering)
                    .padding(.horizontal, 18)
                    .frame(height: NotchPillView.contentHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .notchItemAccessibility(item)
    }

    private func expanded(_ content: PanelContent) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            PanelView(content: content, clock: clock, maxHeight: panelMaxHeight, perform: perform)
                .padding(.bottom, 4)
        }
        // Its own height, not the shape's: the shape follows the content, not the other way.
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onExpandedHeight($0) }
    }
}

/// A shape whose changes are never interpolated.
private struct Unanimated<Base: Shape>: Shape {
    var shape: Base

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func path(in rect: CGRect) -> Path {
        shape.path(in: rect)
    }
}
