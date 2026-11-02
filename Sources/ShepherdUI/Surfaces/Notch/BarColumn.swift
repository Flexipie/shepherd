import ShepherdCore

/// A column of the notch bar. The needs-you queue comes first, pinned on the left; a section of
/// project and repo cards fills two columns, its cards shared out so the columns stay about as
/// long as each other; a section of gadget cards on Gadgets gives one column per card; any other
/// section is one column. So a new module's section just appears as another column, and the
/// keyboard and the view agree on the grid.
struct BarColumn: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable {
        /// The whole section under its title.
        case section
        /// Some of a section's project and repo cards, sharing the width with the other half.
        case projects
        /// One gadget card.
        case card
    }

    let id: String
    let section: PanelSection
    /// The column's cards, or the whole section for a section column.
    let items: [PanelItem]
    let kind: Kind

    static let queueID = "queue"
    /// How many columns a section of project and repo cards fills.
    static let projectColumns = 2

    var isQueue: Bool { section.id == Self.queueID && kind == .section }

    static func layout(_ sections: [PanelSection]) -> [BarColumn] {
        let ordered = sections.filter { $0.id == queueID } + sections.filter { $0.id != queueID }
        return ordered.flatMap { section -> [BarColumn] in
            guard section.id != queueID, !section.items.isEmpty else { return [whole(section)] }
            if let rows = projectRows(section.items) {
                return projects(section, rows: rows)
            }
            // On Gadgets only: the first-run guide and the demo are gadget cards under one title.
            let gadgets = section.items.compactMap { item -> GadgetCard? in
                if case .gadget(let card) = item, section.tab == .gadgets { card } else { nil }
            }
            guard gadgets.count == section.items.count else { return [whole(section)] }
            return gadgets.map { card in
                BarColumn(id: "\(section.id)/gadget/\(card.id)", section: section, items: [.gadget(card)], kind: .card)
            }
        }
    }

    private static func whole(_ section: PanelSection) -> BarColumn {
        BarColumn(id: section.id, section: section, items: section.items, kind: .section)
    }

    /// How many rows each card takes, or nil unless every item is a project or repo card.
    private static func projectRows(_ items: [PanelItem]) -> [Int]? {
        let rows = items.compactMap { item -> Int? in
            switch item {
            // A project with one agent is a single row, as a repo's checkout with one is.
            case .project(let card): RepoCard.soleAgent(card) == nil ? 1 + card.agents.count : 1
            case .repo(let card): 1 + card.projects.reduce(0) { $0 + max(1, $1.agents.count) }
            default: nil
            }
        }
        return rows.count == items.count ? rows : nil
    }

    /// Each card goes to the shorter column, the first on a tie.
    private static func projects(_ section: PanelSection, rows: [Int]) -> [BarColumn] {
        var columns = Array(repeating: (items: [PanelItem](), rows: 0), count: min(projectColumns, rows.count))
        for (item, count) in zip(section.items, rows) {
            let shortest = columns.indices.min { columns[$0].rows < columns[$1].rows }!
            columns[shortest].items.append(item)
            columns[shortest].rows += count
        }
        return columns.enumerated().map { index, column in
            BarColumn(id: "\(section.id)/\(index)", section: section, items: column.items, kind: .projects)
        }
    }
}
