import ShepherdCore

/// Something in the panel that can be selected with the keyboard and chosen with Return. The same
/// agent can appear twice (in the queue and in its card), so the id includes the section.
public struct PanelTarget: Sendable, Hashable, Identifiable {
    public typealias ID = String
    public let id: ID
    public let action: PanelAction
    /// The notch bar column it sits in, and its place in that column. The menu bar panel is one
    /// column.
    public let column: Int
    public let row: Int

    public enum Direction: Sendable {
        case up, down, left, right
    }

    static func id(section: String, action: PanelAction) -> ID {
        switch action {
        case .jump(let agent): "\(section)/agent/\(agent)"
        case .focusProject(let project): "\(section)/project/\(project)"
        }
    }

    static func actions(in items: [PanelItem]) -> [PanelAction] {
        items.flatMap { item -> [PanelAction] in
            switch item {
            case .agent(let row): [row.action].compactMap { $0 }
            case .project(let card): ([card.action] + card.agents.map(\.action)).compactMap { $0 }
            case .usage, .notice: []
            }
        }
    }

    /// Every selectable item, top to bottom, as one column.
    public static func all(in sections: [PanelSection]) -> [PanelTarget] {
        sections
            .flatMap { section in actions(in: section.items).map { (section.id, $0) } }
            .enumerated()
            .map { row, target in PanelTarget(id: id(section: target.0, action: target.1), action: target.1, column: 0, row: row) }
    }

    /// Every selectable item in the notch bar, column by column.
    static func all(in columns: [BarColumn]) -> [PanelTarget] {
        columns.enumerated().flatMap { column, bar in
            actions(in: bar.items).enumerated().map { row, action in
                PanelTarget(id: id(section: bar.section.id, action: action), action: action, column: column, row: row)
            }
        }
    }

    /// The next selection after moving `offset` items from `current`, clamped to the ends. With
    /// nothing selected, down picks the first item and up the last.
    public static func move(from current: ID?, by offset: Int, in targets: [PanelTarget]) -> ID? {
        guard !targets.isEmpty else { return nil }
        guard let current, let index = targets.firstIndex(where: { $0.id == current }) else {
            return offset >= 0 ? targets.first?.id : targets.last?.id
        }
        return targets[min(max(index + offset, 0), targets.count - 1)].id
    }

    /// The next selection in a grid of columns. Up and down stay in the column, clamped to its
    /// ends; left and right go to the nearest row of the next column that has any. With nothing
    /// selected, down and right pick the first item, up and left the last.
    public static func move(from current: ID?, _ direction: Direction, in targets: [PanelTarget]) -> ID? {
        guard !targets.isEmpty else { return nil }
        guard let current, let here = targets.first(where: { $0.id == current }) else {
            return direction == .up || direction == .left ? targets.last?.id : targets.first?.id
        }
        switch direction {
        case .up, .down:
            let column = targets.filter { $0.column == here.column }
            let row = min(max(here.row + (direction == .down ? 1 : -1), 0), column.count - 1)
            return column[row].id
        case .left, .right:
            let columns = Set(targets.map(\.column))
            let next = direction == .right ? columns.filter { $0 > here.column }.min() : columns.filter { $0 < here.column }.max()
            guard let next else { return here.id }
            let column = targets.filter { $0.column == next }
            return column[min(here.row, column.count - 1)].id
        }
    }
}

/// What choosing a row in the notch bar does. With ⌘ (click or Return) an agent's row jumps
/// straight to it; otherwise it opens the agent's stage when the bar has one. Anything else, such
/// as a project header, does what it always does.
enum BarChoice: Equatable {
    case perform(PanelAction)
    case openStage(AgentID)

    static func choose(_ action: PanelAction, command: Bool, hasStage: Bool) -> BarChoice {
        if !command, hasStage, case .jump(let agent) = action { return .openStage(agent) }
        return .perform(action)
    }
}
