import ShepherdCore
import SwiftUI

/// The notch's expanded state: a wide, short bar along the top of the screen. The Agents | Gadgets
/// tabs sit on top when any gadget is on. On Agents the needs-you queue is pinned on the left,
/// then one column per project card (or per other section), scrolling sideways when there are
/// many; on Gadgets each gadget is a column. Each column scrolls on its own past `maxHeight`.
/// Status lines and config problems share one quiet line along the bottom. Arrows move across
/// the grid, Return chooses, hovering selects, ⌘1 and ⌘2 switch tabs.
///
/// With `onStage`, choosing an agent's row opens its stage in place of the project columns
/// instead of jumping, and `offersNewTask` adds a "+" after the columns for the new task form.
/// Both are on the Agents tab only.
/// Escape or Left goes back, a digit picks one of a stage's choices. The arrow on a hovered or
/// selected row, ⌘-click and ⌘Return jump straight to the agent.
public struct NotchBarView: View {
    let content: PanelContent
    let clock: PanelClock
    let width: CGFloat
    let maxHeight: CGFloat?
    let stage: BarStage?
    let offersNewTask: Bool
    let tab: PanelTab
    let onTab: (PanelTab) -> Void
    let perform: (PanelAction) -> Void
    let onStage: ((StageAction) -> Void)?

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
                stage: BarStage? = nil, offersNewTask: Bool = false, tab: PanelTab = .agents,
                onTab: @escaping (PanelTab) -> Void = { _ in }, selection: PanelTarget.ID? = nil,
                perform: @escaping (PanelAction) -> Void, onStage: ((StageAction) -> Void)? = nil) {
        self.content = content
        self.clock = clock
        self.width = width
        self.maxHeight = maxHeight
        self.offersNewTask = offersNewTask
        self.tab = tab
        self.onTab = onTab
        // A stage replaces the project columns, which only Agents has.
        self.stage = content.shownTab(tab) == .agents ? stage : nil
        self.perform = perform
        self.onStage = onStage
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
        .onKeyPress(.leftArrow) { stage == nil ? move(.left) : closeStage() }
        .onKeyPress(.rightArrow) { stage == nil ? move(.right) : .handled }
        .onKeyPress(.escape) { stage == nil ? .ignored : closeStage() }
        .onKeyPress(characters: .decimalDigits) { press in
            press.modifiers.contains(.command) ? switchTab(press.characters) : pick(press.characters)
        }
        .onKeyPress(.return, phases: .down) { press in choose(command: press.modifiers.contains(.command)) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: content)
    }

    private var columns: [BarColumn] { BarColumn.layout(content.sections(on: tab)) }

    private func bar(now: Date) -> some View {
        let columns = self.columns
        let pinned = columns.first.flatMap { $0.isQueue ? $0 : nil }
        let rest = pinned == nil ? columns : Array(columns.dropFirst())
        return VStack(alignment: .leading, spacing: 0) {
            if content.hasTabs {
                PanelTabBar(selected: content.shownTab(tab), onTab: onTab)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            }
            HStack(alignment: .top, spacing: Self.spacing) {
                if let pinned {
                    column(pinned, now: now)
                }
                if pinned != nil, stage != nil || !rest.isEmpty || newTaskButton {
                    Divider()
                }
                switch (stage, onStage) {
                case (.agent(let stage)?, let onStage?):
                    StageView(stage: stage, now: now, linesHeight: maxHeight.map { max(60, $0 - Self.stageChrome) },
                              perform: perform, onStage: onStage)
                        .id(stage.agent)
                case (.newTask(let stage)?, let onStage?):
                    NewTaskView(stage: stage, onStage: onStage)
                default:
                    if !rest.isEmpty || newTaskButton { scrolling(rest, now: now) }
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
            if newTaskButton {
                NewTaskButton { onStage?(.newTask) }
            }
        }
        if let maxHeight {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { row }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .frame(height: min(max(columns.compactMap { heights[$0.id] }.max() ?? 0, newTaskButton ? 64 : 0), maxHeight))
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
                          jump: perform, perform: barPerform) { selection = $0 }
        } else {
            PanelSectionView(section: column.section, now: now, selection: selection, jump: perform,
                             perform: barPerform) { selection = $0 }
        }
    }

    /// Room the stage needs around its lines: its header and an error line.
    static let stageChrome: CGFloat = 58

    private var newTaskButton: Bool { offersNewTask && onStage != nil && content.shownTab(tab) == .agents }

    /// Agent rows open their stage when there is one to open; anything else, such as a project
    /// header, does what it always does.
    private func barPerform(_ action: PanelAction) {
        run(.choose(action, command: false, hasStage: onStage != nil))
    }

    private func run(_ choice: BarChoice) {
        switch choice {
        case .perform(let action): perform(action)
        case .openStage(let agent): onStage?(.open(agent))
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

    private func choose(command: Bool) -> KeyPress.Result {
        guard let target = PanelTarget.all(in: columns).first(where: { $0.id == selection }) else { return .ignored }
        run(.choose(target.action, command: command, hasStage: onStage != nil))
        return .handled
    }

    private func closeStage() -> KeyPress.Result {
        onStage?(.close)
        return .handled
    }

    /// ⌘1 and ⌘2 pick a tab.
    private func switchTab(_ characters: String) -> KeyPress.Result {
        guard content.hasTabs, let next = PanelTab.forDigit(characters) else { return .ignored }
        if next != content.shownTab(tab) { onTab(next) }
        return .handled
    }

    /// A digit picks the staged agent's choice with that key.
    private func pick(_ key: String) -> KeyPress.Result {
        guard case .agent(let stage)? = stage, stage.canSendKeys, !stage.isSending, stage.choices.contains(where: { $0.key == key }) else { return .ignored }
        onStage?(.keys([key]))
        return .handled
    }
}
