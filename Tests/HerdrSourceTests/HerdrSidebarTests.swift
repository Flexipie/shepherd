import Foundation
import Testing
@testable import HerdrSource
@testable import ShepherdCore

/// A sanitised herdr config with the same structure as a real one: key tables, arrays of tables,
/// comments, multi-line rows with inline tables and rules.
let sampleHerdrConfig = #"""
# herdr config
onboarding = false

[keys]
prefix = "ctrl+b"
split_vertical = "%"   # comment after a value
quit = 'q'

[ui]
theme = "catppuccin"
sidebar_width = 26
accent = "#89b4fa"

[ui.toast]
enabled = true
delay_ms = 1_500

[keys.indexed]
workspace = ["1", "2", "3"]

[[keys.command]]
key = "g"
run = "lazygit # not a comment"

[[keys.command]]
key = "r"
run = """
echo "multi-line" \
  run
"""
rows = [["$should_not_match"]]

[ui.sidebar.spaces]
rows = [
  ["state_icon", "workspace"],
  ["branch", "git_status"],
  # One short group per row
  [{ token = "$pr", fg = "#94e2d5", rules = [{ contains = "draft", dim = true }] }, { token = "$ticket_state", rules = [{ contains = "review", fg = "#cba6f7" }, { contains = "done", fg = "#a6e3a1" }, { contains = "cancel", dim = true }] }],
  [{ token = "$diff_add", fg = "#a6e3a1" }, { token = "$diff_del", fg = "#f38ba8" }, { token = "$diff_files", dim = true }],
  [{ token = "$review", rules = [{ contains = "blocking", fg = "#f38ba8" }, { equals = "none", hide = true }] }],
]

[experimental]
pane_history = true
started = 1979-05-27 07:32:00Z
"""#

@Suite struct TOMLSubsetTests {
    func document(_ text: String) -> TOMLDocument { TOMLDocument(Data(text.utf8)) }

    @Test func readsTheWholeFile() {
        let toml = document(sampleHerdrConfig)
        #expect(toml.problems.isEmpty, "\(toml.problems)")
        #expect(toml.value(at: ["onboarding"])?.value == .bool(false))
        #expect(toml.value(at: ["keys", "split_vertical"])?.value == .string("%"))
        #expect(toml.value(at: ["keys", "quit"])?.value == .string("q"))
        #expect(toml.value(at: ["ui", "toast", "delay_ms"])?.value == .integer(1500))
        #expect(toml.value(at: ["keys", "indexed", "workspace"])?.value == .array([.string("1"), .string("2"), .string("3")]))
        #expect(toml.value(at: ["experimental", "pane_history"])?.value == .bool(true))
        // Keys under [[keys.command]] never match ordinary paths.
        #expect(toml.value(at: ["keys", "command", "key"]) == nil)
        #expect(toml.value(at: ["keys", "command", "[]", "run"])?.value == .opaque("\"\"\"\necho \"multi-line\" \\\n  run\n\"\"\""))
        let rows = toml.value(at: ["ui", "sidebar", "spaces", "rows"])
        #expect(rows?.line == 34)
        guard case .array(let lines)? = rows?.value else { Issue.record("no rows"); return }
        #expect(lines.count == 5)
    }

    @Test func dottedKeysAndInlineTablesShareOnePath() {
        let toml = document("""
        [ui]
        sidebar.agents = { rows = [["$a"]], gap = 1 }
        """)
        #expect(toml.value(at: ["ui", "sidebar", "agents", "rows"])?.value == .array([.array([.string("$a")])]))
    }

    @Test func stringsWithEscapes() {
        let toml = document(##"""
        a = "tab\tquote\" hash # here \u00e9 \U0001F411"
        b = 'C:\path\#'
        "quoted key" = 1
        c = -0.5e1
        d = 0x1F
        """##)
        #expect(toml.problems.isEmpty)
        #expect(toml.value(at: ["a"])?.value == .string("tab\tquote\" hash # here é 🐑"))
        #expect(toml.value(at: ["b"])?.value == .string(##"C:\path\#"##))
        #expect(toml.value(at: ["quoted key"])?.value == .integer(1))
        #expect(toml.value(at: ["c"])?.value == .float(-5))
        #expect(toml.value(at: ["d"])?.value == .integer(31))
    }

    @Test func byteOrderMarkAndCRLF() {
        let toml = TOMLDocument(Data([0xEF, 0xBB, 0xBF]) + Data("[ui]\r\nx = [\r\n  1, # one\r\n  2,\r\n]\r\ny = true\r\n".utf8))
        #expect(toml.problems.isEmpty)
        #expect(toml.value(at: ["ui", "x"])?.value == .array([.integer(1), .integer(2)]))
        #expect(toml.value(at: ["ui", "y"])?.value == .bool(true))
    }

    @Test func aMalformedLineSkipsToTheNextTable() {
        let toml = document("""
        [keys]
        a = "unterminated
        b = 2
        [ui.sidebar.spaces]
        rows = [["$pr"]]
        c = nope
        [after]
        d = 1
        """)
        #expect(toml.problems == [TOMLDocument.Problem(line: 2, message: "unterminated string"),
                                  TOMLDocument.Problem(line: 6, message: "invalid value nope")])
        #expect(toml.value(at: ["keys", "b"]) == nil)
        #expect(toml.value(at: ["ui", "sidebar", "spaces", "rows"])?.value == .array([.array([.string("$pr")])]))
        #expect(toml.value(at: ["after", "d"])?.value == .integer(1))
    }
}

@Suite struct HerdrSidebarTests {
    @Test func takesPluginTokensFromSpaceRows() throws {
        let (layout, problems) = HerdrSidebar.read(Data(sampleHerdrConfig.utf8))
        #expect(problems.isEmpty)
        let projects = try #require(layout?.projects)
        #expect(layout?.agents == nil)
        #expect(projects.map { $0.map(\.name) } == [[], [], ["pr", "ticket_state"], ["diff_add", "diff_del", "diff_files"], ["review"]])
        #expect(projects[2][0] == TokenEntry(name: "pr", style: TokenStyle(fg: HexColor("#94e2d5")),
                                             rules: [TokenRule(.contains("draft"), style: TokenStyle(dim: true))]))
        let lines = TokenStyler.lines(projects, values: ["pr": "#12 draft", "review": "none", "diff_add": "+3"])
        #expect(lines == [[StyledToken(name: "pr", text: "#12 draft", fg: HexColor("#94e2d5"), dim: true)],
                          [StyledToken(name: "diff_add", text: "+3", fg: HexColor("#a6e3a1"))]])
    }

    @Test func agentRowsStyleAgents() {
        let (layout, _) = HerdrSidebar.read(Data("[ui.sidebar.agents]\nrows = [[\"agent\", \"$summary\"]]\n".utf8))
        #expect(layout == TokenLayout(agents: [[TokenEntry(name: "summary")]]))
    }

    @Test func badRowsAreReportedWithTheirLine() {
        let (layout, problems) = HerdrSidebar.read(Data("""
        [keys]
        x = [
        [ui.sidebar.spaces]
        rows = [[{ token = "$pr", fg = "teal" }]]
        """.utf8))
        #expect(layout == nil)
        #expect(problems == ["herdr config line 3: invalid value ui.sidebar.spaces",
                             "herdr config line 4: ui.sidebar.spaces.rows[0][0].fg: must be #RGB or #RRGGBB"])
    }

    @Test func noFileOrNoRowsMeansNoLayout() {
        #expect(HerdrSidebar.read(nil).layout == nil)
        #expect(HerdrSidebar.read(nil).problems.isEmpty)
        #expect(HerdrSidebar.read(Data("[ui]\ntheme = \"x\"\n".utf8)).layout == nil)
    }

    @Test func configPathFollowsHerdr() {
        #expect(HerdrSidebar.configURL(environment: ["HERDR_CONFIG_PATH": "/tmp/h.toml"]).path == "/tmp/h.toml")
        #expect(HerdrSidebar.configURL(environment: [:]).path.hasSuffix("/.config/herdr/config.toml"))
    }
}
