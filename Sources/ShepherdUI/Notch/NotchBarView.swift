import ShepherdCore
import SwiftUI

/// The notch's expanded state: a wide, short bar along the top of the screen. The needs-you queue
/// is pinned on the left, then one column per project card (or per other section), scrolling
/// sideways when there are many; each column scrolls on its own past `maxHeight`. Status lines
/// and config problems share one quiet line along the bottom. Arrows move across the grid,
/// Return chooses, hovering selects.
public struct NotchBarView: View {
    let content: PanelContent
    let clock: PanelClock
    let width: CGFloat
    let maxHeight: CGFloat?
    let perform: (PanelAction) -> Void

    @State private var selection: PanelTarget.ID?
    /// Set by the keyboard only, so hovering never scrolls the row under the mouse.
    @State private var scrollTarget: PanelTarget.ID?
    @State private var heights: [BarColumn.ID: CGFloat] = [:]
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public nonisolated static let queueWidth: CGFloat = 300
    public nonisolated static let columnWidth: CGFloat = 230
    static let spacing: CGFloat = 8

    /// `maxHeight` makes each column scroll past that height; nil lets the columns grow (and,
    /// for snapshots, cuts off the columns that do not fit instead of scrolling them).
    public init(content: PanelContent, clock: PanelClock = .live, width: CGFloat, maxHeight: CGFloat? = nil,
                selection: PanelTarget.ID? = nil, perform: @escaping (PanelAction) -> Void) {
        self.content = content
        self.clock = clock
        self.width = width
        self.maxHeight = maxHeight
        self.perform = perform
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        Group {
            switch clock {
            case .live: TimelineView(.everyMinute) { context in bar(now: context.date) }
            case .fixed(let date): bar(now: date)
            }
        }
        .frame(width: width)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.return) { choose() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: content)
    }

    private var columns: [BarColumn] { BarColumn.layout(content.sections) }

    private func bar(now: Date) -> some View {
        let columns = self.columns
        let pinned = columns.first.flatMap { $0.isQueue ? $0 : nil }
        let rest = pinned == nil ? columns : Array(columns.dropFirst())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Self.spacing) {
                if let pinned {
                    column(pinned, now: now)
                }
                if pinned != nil, !rest.isEmpty {
                    Divider()
                }
                if !rest.isEmpty {
                    scrolling(rest, now: now)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            footer
        }
    }

    @ViewBuilder
    private func scrolling(_ columns: [BarColumn], now: Date) -> some View {
        let row = HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(columns) { column in
                self.column(column, now: now).id(column.id)
            }
        }
        if let maxHeight {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { row }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .frame(height: min(columns.compactMap { heights[$0.id] }.max() ?? 0, maxHeight))
                    .onChange(of: scrollTarget) { _, target in
                        guard let target, let column = columns.first(where: { contains($0, target) }) else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(column.id) }
                    }
            }
        } else {
            row.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
        }
    }

    @ViewBuilder
    private func column(_ column: BarColumn, now: Date) -> some View {
        let items = columnItems(column, now: now)
            .frame(width: column.isQueue ? Self.queueWidth : Self.columnWidth, alignment: .topLeading)
        if let maxHeight {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    items.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[column.id] = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(heights[column.id] ?? 0, maxHeight))
                .onChange(of: scrollTarget) { _, target in
                    guard let target, contains(column, target) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(Optional(target)) }
                }
            }
        } else {
            items
        }
    }

    @ViewBuilder
    private func columnItems(_ column: BarColumn, now: Date) -> some View {
        if column.isCard, let item = column.items.first {
            PanelItemView(item: item, sectionID: column.section.id, now: now, selection: selection,
                          perform: perform) { selection = $0 }
        } else {
            PanelSectionView(section: column.section, now: now, selection: selection, perform: perform) { selection = $0 }
        }
    }

    private func contains(_ column: BarColumn, _ target: PanelTarget.ID) -> Bool {
        PanelTarget.all(in: [column]).contains { $0.id == target }
    }

    @ViewBuilder
    private var footer: some View {
        if !content.statusLines.isEmpty || !content.problems.isEmpty {
            HStack(spacing: 10) {
                if !content.problems.isEmpty {
                    Label {
                        Text(content.problems.joined(separator: "; "))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .layoutPriority(1)
                }
                Text(content.statusLines.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
            .help((content.problems + content.statusLines).joined(separator: "\n"))
        }
    }

    private func move(_ direction: PanelTarget.Direction) -> KeyPress.Result {
        selection = PanelTarget.move(from: selection, direction, in: PanelTarget.all(in: columns))
        scrollTarget = selection
        return .handled
    }

    private func choose() -> KeyPress.Result {
        guard let target = PanelTarget.all(in: columns).first(where: { $0.id == selection }) else { return .ignored }
        perform(target.action)
        return .handled
    }
}
