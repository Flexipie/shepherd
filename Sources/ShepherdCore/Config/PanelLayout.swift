import Foundation

/// Which sections each tab shows, in what order, and which project columns come first. Shared by
/// the menu bar panel and the notch bar. Every part left out keeps the default: a tab's sections
/// in module order, projects in source order.
public struct PanelLayout: Sendable, Equatable {
    /// Section (module) ids per tab, in order; a section on that tab left out is hidden. A tab
    /// with no list shows all of its sections.
    public var tabs: [PanelTab: [String]]
    /// Project or repo names whose cards come first, in this order; the rest follow in source
    /// order. Matched without regard to case.
    public var projects: [String]

    public init(tabs: [PanelTab: [String]] = [:], projects: [String] = []) {
        self.tabs = tabs
        self.projects = projects
    }

    /// Every section id the tab lists name, for checking them against the known modules.
    public var sectionIDs: [String] { PanelTab.allCases.flatMap { tabs[$0] ?? [] } }

    /// The sections to show: each tab with a list keeps only the listed sections, in list order,
    /// at the place of the tab's first section; other tabs are untouched.
    public func arrange(_ sections: [PanelSection]) -> [PanelSection] {
        guard !tabs.isEmpty else { return sections }
        var placed: Set<PanelTab> = []
        return sections.flatMap { section -> [PanelSection] in
            guard let ids = tabs[section.tab] else { return [section] }
            guard placed.insert(section.tab).inserted else { return [] }
            let onTab = sections.filter { $0.tab == section.tab }
            var seen: Set<String> = []
            return ids.compactMap { id in seen.insert(id).inserted ? onTab.first { $0.id == id } : nil }
        }
    }

    /// A listed id whose section sits on the other tab, which a list cannot move it to: said in
    /// the footer, since its own tab would otherwise just lose sections without a word.
    public func problems(_ sections: [PanelSection]) -> [String] {
        PanelTab.allCases.flatMap { tab in
            (tabs[tab] ?? []).compactMap { id in
                sections.first { $0.id == id && $0.tab != tab }.map { "config: layout.\(tab.rawValue): \"\(id)\" is on the \($0.tab.title) tab" }
            }
        }
    }

    /// Project and repo cards named in `projects` first, in that order, then the rest as they were.
    /// A card answers to its project's name and its repo's, so a project keeps its place when a
    /// second checkout turns it into a repo card.
    public func orderProjects(_ items: [PanelItem]) -> [PanelItem] {
        guard !projects.isEmpty else { return items }
        let names = projects.map { $0.lowercased() }
        func rank(_ item: PanelItem) -> Int {
            let candidates: [String] = switch item {
            case .project(let card): [card.project.name] + (card.project.repo.map { [$0.name] } ?? [])
            case .repo(let card): [card.name] + card.projects.map(\.project.name)
            default: []
            }
            return candidates.compactMap { names.firstIndex(of: $0.lowercased()) }.min() ?? names.count
        }
        return items.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Reads `layout`: `agents` and `gadgets`, lists of section ids, and `projects`, a list of
    /// names. A part that cannot be used is reported and keeps its default.
    static func read(_ value: ConfigValue, problems: inout [String]) -> PanelLayout {
        guard case .table(let keys) = value else {
            problems.append("config: layout must be an object with agents, gadgets and projects")
            return PanelLayout()
        }
        var layout = PanelLayout()
        let tabKeys = PanelTab.allCases.map(\.rawValue)
        for key in keys.keys.sorted() where !(tabKeys + ["projects"]).contains(key) {
            problems.append("config: unknown key \"layout.\(key)\"")
        }
        for tab in PanelTab.allCases {
            guard let list = keys[tab.rawValue] else { continue }
            if let ids = strings(list) {
                layout.tabs[tab] = ids
            } else {
                problems.append("config: layout.\(tab.rawValue) must be a list of section ids")
            }
        }
        if let list = keys["projects"] {
            if let names = strings(list) {
                layout.projects = names
            } else {
                problems.append("config: layout.projects must be a list of project names")
            }
        }
        return layout
    }

    private static func strings(_ value: ConfigValue) -> [String]? {
        guard case .array(let items) = value else { return nil }
        let strings = items.compactMap { item -> String? in if case .string(let string) = item { string } else { nil } }
        return strings.count == items.count ? strings : nil
    }
}
