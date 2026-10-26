import Foundation
import Testing
@testable import ShepherdCore

@Suite struct PanelLayoutTests {
    func read(_ json: String) throws -> (layout: PanelLayout, problems: [String]) {
        let (config, problems) = try ShepherdConfig.read(Data(json.utf8))
        return (config.layout, problems)
    }

    static func section(_ id: String, _ tab: PanelTab = .agents) -> PanelSection {
        PanelSection(id: id, title: id, items: [], emptyText: "", tab: tab)
    }

    func card(_ name: String) -> PanelItem {
        .project(PanelProjectCard(project: HerdProject(id: ProjectID(source: "herdr", local: name), name: name), agents: []))
    }

    func names(_ items: [PanelItem]) -> [String] {
        items.map { item in
            switch item {
            case .project(let card): card.project.name
            case .repo(let card): card.name
            default: "?"
            }
        }
    }

    let sections = [section("queue"), section("usage", .gadgets), section("system", .gadgets), section("projects")]

    @Test func leftOutKeepsEverySectionInModuleOrder() throws {
        let (layout, problems) = try read("{}")
        #expect(layout == PanelLayout())
        #expect(problems.isEmpty)
        #expect(layout.arrange(sections).map(\.id) == ["queue", "usage", "system", "projects"])
        #expect(names(layout.orderProjects([card("b"), card("a")])) == ["b", "a"])
    }

    @Test func badPartsAreReportedAndKeepTheirDefaults() throws {
        let (layout, problems) = try read(#"{"layout": {"agents": "queue", "gadgets": ["usage"], "projects": [1], "tabs": []}}"#)
        #expect(layout == PanelLayout(tabs: [.gadgets: ["usage"]]))
        #expect(problems == [
            "config: unknown key \"layout.tabs\"",
            "config: layout.agents must be a list of section ids",
            "config: layout.projects must be a list of project names",
        ])
        #expect(try read(#"{"layout": []}"#).problems == ["config: layout must be an object with agents, gadgets and projects"])
    }
}
