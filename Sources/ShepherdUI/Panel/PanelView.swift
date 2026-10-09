import ShepherdCore
import SwiftUI

/// Everything the panel shows, computed by the app from the modules and the store.
public struct PanelContent: Sendable, Equatable {
    public var sections: [PanelSection]
    /// The herd's state, then each source's own lines.
    public var statusLines: [String]
    /// Config problems, shown so a broken edit is never silent.
    public var problems: [String]

    public init(sections: [PanelSection], statusLines: [String] = [], problems: [String] = []) {
        self.sections = sections
        self.statusLines = statusLines
        self.problems = problems
    }
}

/// Where the panel's "now" comes from. Views never read the clock themselves, so times tick
/// once a minute while the panel exists and snapshots are stable.
public enum PanelClock: Sendable {
    case live
    case fixed(Date)
}

/// The panel under the menu bar icon: the needs-you queue, then a card per project, then status
/// and problems. Up and down move the selection, Return chooses it, hovering selects.
public struct PanelView: View {
    let content: PanelContent
    let clock: PanelClock
    let maxHeight: CGFloat?
    let perform: (PanelAction) -> Void

    @State private var selection: PanelTarget.ID?
    @State private var contentHeight: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public nonisolated static let width: CGFloat = 360

    /// `maxHeight` makes the sections scroll past that height; nil lets the view grow.
    public init(content: PanelContent, clock: PanelClock = .live, maxHeight: CGFloat? = nil,
                selection: PanelTarget.ID? = nil, perform: @escaping (PanelAction) -> Void) {
        self.content = content
        self.clock = clock
        self.maxHeight = maxHeight
        self.perform = perform
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        Group {
            switch clock {
            case .live: TimelineView(.everyMinute) { context in panel(now: context.date) }
            case .fixed(let date): panel(now: date)
            }
        }
        .frame(width: Self.width)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.return) { choose() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: content)
    }

    private func panel(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let maxHeight {
                ScrollView {
                    sections(now: now)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(contentHeight, maxHeight))
            } else {
                sections(now: now)
            }
            footer
        }
    }

    private func sections(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(content.sections) { section in
                sectionView(section, now: now)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func sectionView(_ section: PanelSection, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if section.id == "queue", !section.items.isEmpty {
                    Text("\(section.items.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            if section.items.isEmpty {
                Text(section.emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(section.items.indices, id: \.self) { index in
                item(section.items[index], section: section.id, now: now)
            }
        }
    }

    @ViewBuilder
    private func item(_ item: PanelItem, section: String, now: Date) -> some View {
        switch item {
        case .agent(let row):
            let id = row.action.map { PanelTarget.id(section: section, action: $0) }
            AgentRow(row: row, now: now, showsProject: true, isSelected: id != nil && id == selection)
                .onTapGesture { if let action = row.action { perform(action) } }
                .onHover { inside in if inside, let id { selection = id } }
        case .project(let card):
            ProjectCard(card: card, now: now, selection: selection, sectionID: section, perform: perform) { id in
                if let id { selection = id }
            }
        case .notice(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !content.statusLines.isEmpty || !content.problems.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(content.problems, id: \.self) { problem in
                    Label {
                        Text(problem).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.system(size: 11))
                }
                ForEach(content.statusLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Divider().padding(.horizontal, 10) }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        selection = PanelTarget.move(from: selection, by: offset, in: PanelTarget.all(in: content.sections))
        return .handled
    }

    private func choose() -> KeyPress.Result {
        guard let target = PanelTarget.all(in: content.sections).first(where: { $0.id == selection }) else { return .ignored }
        perform(target.action)
        return .handled
    }
}
