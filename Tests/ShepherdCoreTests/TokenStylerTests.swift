import Foundation
import Testing
@testable import ShepherdCore

@Suite struct TokenStylerTests {
    let teal = HexColor("#94e2d5")!
    let purple = HexColor("#cba6f7")!
    let red = HexColor("#f38ba8")!

    func styled(_ entry: TokenEntry, _ value: String) -> StyledToken? {
        TokenStyler.style(entry, values: [entry.name: value])
    }

    @Test func firstMatchingRuleWins() {
        let entry = TokenEntry(name: "ticket_state", rules: [
            TokenRule(.contains("review"), style: TokenStyle(fg: purple)),
            TokenRule(.contains("re"), style: TokenStyle(fg: red)),
        ])
        #expect(styled(entry, "in review")?.fg == purple)
        #expect(styled(entry, "ready")?.fg == red)
        #expect(styled(entry, "todo")?.fg == nil)
    }

    @Test func unsetRuleFieldsInherit() {
        let entry = TokenEntry(name: "pr", style: TokenStyle(fg: teal, bold: true),
                               rules: [TokenRule(.contains("draft"), style: TokenStyle(dim: true))])
        #expect(styled(entry, "#12 draft") == StyledToken(name: "pr", text: "#12 draft", fg: teal, bold: true, dim: true))
        #expect(styled(entry, "#12") == StyledToken(name: "pr", text: "#12", fg: teal, bold: true, dim: false))
    }

    @Test func ruleWithoutOverridesStillStopsMatching() {
        let entry = TokenEntry(name: "x", rules: [TokenRule(.equals("a")), TokenRule(.contains("a"), style: TokenStyle(fg: red))])
        #expect(styled(entry, "a")?.fg == nil)
        #expect(styled(entry, "ab")?.fg == red)
    }

    @Test func hideRemovesTheToken() {
        let entry = TokenEntry(name: "review", rules: [TokenRule(.equals("none"), hide: true)])
        #expect(styled(entry, "none") == nil)
        #expect(styled(entry, "safe")?.text == "safe")
    }

    @Test func ignoreCaseIsAsciiOnly() {
        #expect(TokenRule(.equals("Draft"), ignoreCase: true).matches("DRAFT"))
        #expect(!TokenRule(.equals("Draft")).matches("draft"))
        #expect(TokenRule(.startsWith("ci:"), ignoreCase: true).matches("CI: green"))
        #expect(!TokenRule(.equals("é"), ignoreCase: true).matches("É"))
    }

    @Test(arguments: [("90", true, false), ("60", false, true), ("90%", false, false), ("75", false, false),
                      ("-1.5e3", false, true), (" 90", false, false), ("inf", false, false), ("0x60", false, false),
                      ("", false, false), (".5", false, true)])
    func numericRulesNeedAWholeFiniteNumber(value: String, above: Bool, below: Bool) {
        #expect(TokenRule(.greaterThan(80)).matches(value) == above)
        #expect(TokenRule(.lessThan(70)).matches(value) == below)
    }

    @Test func missingTokensAndEmptyLinesDisappear() {
        let layout: [[TokenEntry]] = [
            [TokenEntry(name: "workspace", isBuiltin: true), TokenEntry(name: "pr")],
            [TokenEntry(name: "missing"), TokenEntry(name: "empty")],
            [TokenEntry(name: "review"), TokenEntry(name: "missing")],
        ]
        let lines = TokenStyler.lines(layout, values: ["pr": "#12", "review": "safe", "empty": ""])
        #expect(lines.map { $0.map(\.text) } == [["#12"], ["safe"]])
    }

    @Test func layoutsReplaceRatherThanMerge() {
        let values = ["b": "2", "a": "1", "pr": "#3"]
        let mine = TokenLayout(projects: [[TokenEntry(name: "pr", style: TokenStyle(bold: true))]])
        let source = TokenLayout(projects: [[TokenEntry(name: "a")]], agents: [[TokenEntry(name: "b")]])
        #expect(TokenLayout.lines(.projects, values: values, layouts: [mine, source]).map { $0.map(\.text) } == [["#3"]])
        #expect(TokenLayout.lines(.agents, values: values, layouts: [mine, source]).map { $0.map(\.text) } == [["2"]])
        #expect(TokenLayout.lines(.agents, values: values, layouts: [mine, nil]).map { $0.map(\.text) } == [["1", "2", "#3"]])
        #expect(TokenLayout.lines(.agents, values: [:], layouts: []).isEmpty)
    }

    @Test func readsHerdrStyleEntries() throws {
        let json = """
        {"projects": [[{"token": "$pr", "fg": "#94e2d5", "rules": [{"contains": "draft", "dim": true}]}, "ticket_state", "branch"]],
         "agents": [[{"token": "load", "rules": [{"gt": 80, "fg": "#f38ba8", "bold": true}, {"equals": "Idle", "ignore_case": true, "hide": true}]}]]}
        """
        let layout = try TokenLayout(JSONDecoder().decode(ConfigValue.self, from: Data(json.utf8)))
        let projects = try #require(layout.projects?.first)
        #expect(projects.map(\.name) == ["pr", "ticket_state", "branch"])
        #expect(projects.map(\.isBuiltin) == [false, false, true])
        #expect(projects[0].style == TokenStyle(fg: teal))
        #expect(projects[0].rules == [TokenRule(.contains("draft"), style: TokenStyle(dim: true))])
        let agents = try #require(layout.agents?.first?.first)
        #expect(agents.rules == [TokenRule(.greaterThan(80), style: TokenStyle(fg: red, bold: true)),
                                 TokenRule(.equals("Idle"), ignoreCase: true, hide: true)])
    }

    @Test(arguments: [
        (##"{"projects": [[{"token": "x", "rules": [{"contains": "a", "equals": "b"}]}]]}"##, "projects[0][0].rules[0]: needs exactly one"),
        (##"{"projects": [[{"token": "x", "rules": [{"fg": "#fff"}]}]]}"##, "projects[0][0].rules[0]: needs exactly one"),
        (##"{"projects": [[{"token": "x", "fg": "teal"}]]}"##, "projects[0][0].fg: must be #RGB or #RRGGBB"),
        (##"{"agents": [[{"token": "x", "rules": [{"gt": "80"}]}]]}"##, "agents[0][0].rules[0].gt: expected a number"),
        (##"{"agents": [["x", 3]]}"##, "agents[0][1]: expected a token name or an object"),
        (##"{"agents": ["x"]}"##, "agents[0]: expected a list of tokens"),
        (##"{"agents": [[{"fg": "#fff"}]]}"##, "agents[0][0]: missing \"token\""),
    ])
    func rejectsWhatHerdrRejects(json: String, message: String) throws {
        let value = try JSONDecoder().decode(ConfigValue.self, from: Data(json.utf8))
        #expect(throws: ConfigProblem.self) { try TokenLayout(value) }
        do { _ = try TokenLayout(value) } catch { #expect(error.message.hasPrefix(message), "\(error.message)") }
    }

    @Test func atMostSixteenRules() throws {
        let rules = ConfigValue.array(Array(repeating: .table(["equals": .string("a")]), count: 17))
        let value = ConfigValue.table(["agents": .array([.array([.table(["token": .string("x"), "rules": rules])])])])
        #expect(throws: ConfigProblem("agents[0][0].rules: at most 16 rules")) { try TokenLayout(value) }
    }
}

@Suite struct HexColorTests {
    @Test func parsesShortAndLongForms() {
        #expect(HexColor("#abc") == HexColor(red: 0xaa, green: 0xbb, blue: 0xcc))
        #expect(HexColor("#94E2D5")?.description == "#94e2d5")
        #expect(HexColor("94e2d5") == nil)
        #expect(HexColor("#94e2d") == nil)
        #expect(HexColor("#ggg") == nil)
    }

    @Test func contrastMatchesWcag() {
        let black = HexColor("#000")!, white = HexColor("#fff")!
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(white.contrast(with: white) == 1)
    }

    @Test func pastelsAreDarkenedOnLightBackgrounds() {
        let pastel = HexColor("#94e2d5")!
        let light = HexColor.lightBackground
        #expect(pastel.contrast(with: light) < 4.5)
        let fixed = pastel.readable(on: light)
        #expect(fixed.contrast(with: light) >= 4.5)
        #expect(fixed.luminance < pastel.luminance)
        // Only as far as needed: one step less would not pass.
        #expect(fixed.contrast(with: light) < 5.2)
    }

    @Test func readableColoursAreUnchanged() {
        let dark = HexColor.darkBackground
        for text in ["#94e2d5", "#cba6f7", "#a6e3a1", "#f38ba8"] {
            #expect(HexColor(text)!.readable(on: dark) == HexColor(text)!)
        }
        #expect(HexColor("#1e3a8a")!.readable(on: .lightBackground) == HexColor("#1e3a8a")!)
        #expect(HexColor("#333")!.readable(on: dark).contrast(with: dark) >= 4.5)
    }
}
