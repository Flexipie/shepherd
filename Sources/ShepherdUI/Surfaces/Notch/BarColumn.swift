import ShepherdCore

/// A column of the notch bar. The needs-you queue comes first, pinned on the left; a section of
/// project and repo cards gives one column per card; any other section is one column. So a new module's
/// section just appears as another column, and the keyboard and the view agree on the grid.
struct BarColumn: Sendable, Equatable, Identifiable {
    let id: String
    let section: PanelSection
    /// One card for a card column, the whole section otherwise.
    let items: [PanelItem]
    /// A card carries its own title; a section column shows the section's.
    let isCard: Bool

    static let queueID = "queue"

    var isQueue: Bool { section.id == Self.queueID && !isCard }

    static func layout(_ sections: [PanelSection]) -> [BarColumn] {
        let ordered = sections.filter { $0.id == queueID } + sections.filter { $0.id != queueID }
        return ordered.flatMap { section -> [BarColumn] in
            let cards = section.items.compactMap { item -> (id: String, item: PanelItem)? in
                switch item {
                case .project(let card): ("\(section.id)/\(card.project.id)", item)
                case .repo(let card): ("\(section.id)/repo/\(card.key)", item)
                default: nil
                }
            }
            guard section.id != queueID, !cards.isEmpty, cards.count == section.items.count else {
                return [BarColumn(id: section.id, section: section, items: section.items, isCard: false)]
            }
            return cards.map { card in
                BarColumn(id: card.id, section: section, items: [card.item], isCard: true)
            }
        }
    }
}
