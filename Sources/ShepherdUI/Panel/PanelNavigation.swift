import ShepherdCore

/// Something in the panel that can be selected with the keyboard and chosen with Return. The same
/// agent can appear twice (in the queue and in its card), so the id includes the section.
public struct PanelTarget: Sendable, Hashable, Identifiable {
    public typealias ID = String
    public let id: ID
    public let action: PanelAction

    static func id(section: String, action: PanelAction) -> ID {
        switch action {
        case .jump(let agent): "\(section)/agent/\(agent)"
        case .focusProject(let project): "\(section)/project/\(project)"
        }
    }

    /// Every selectable item, top to bottom.
    public static func all(in sections: [PanelSection]) -> [PanelTarget] {
        sections.flatMap { section in
            section.items.flatMap { item -> [PanelAction] in
                switch item {
                case .agent(let row): [row.action].compactMap { $0 }
                case .project(let card): ([card.action] + card.agents.map(\.action)).compactMap { $0 }
                case .notice: []
                }
            }
            .map { PanelTarget(id: id(section: section.id, action: $0), action: $0) }
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
}
