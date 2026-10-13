import Testing
@testable import ShepherdCore

/// Sanitised screens in the shape of real approval prompts: no real paths, commands or names.
@Suite struct ChoiceParserTests {
    static let claudeBoxed = """
    ⏺ I'll run the tests.

    ╭──────────────────────────────────────────────────────────────╮
    │ Bash command                                                 │
    │                                                              │
    │   make test                                                  │
    │   Run the test suite                                         │
    │                                                              │
    │ Do you want to proceed?                                      │
    │ ❯ 1. Yes                                                     │
    │   2. Yes, and don't ask again for make commands in /work/app │
    │   3. No, and tell Claude what to do differently (esc)        │
    ╰──────────────────────────────────────────────────────────────╯
    """

    static let claudeOpen = """
     Edit file

     src/module.swift
     ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
      12 -    let a = 1
      12 +    let a = 2
     ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
     Do you want to make this edit to module.swift?
     ❯ 1. Yes
       2. Yes, allow all edits during this session (shift+tab)
       3. No, and tell Claude what to do differently (esc)
    """

    static let codex = """
    • Running make test

      Would you like to run the following command?

      $ make test

    › 1. Yes, proceed (y)
      2. Yes, and don't ask again for this command (a)
      3. No, and tell Codex what to do differently (esc)

      Press enter to confirm or esc to cancel
    """

    @Test func claudeCodeBoxedPrompt() {
        let choices = ChoiceParser.choices(in: Self.claudeBoxed)
        #expect(choices.map(\.key) == ["1", "2", "3"])
        #expect(choices[0] == AgentChoice(key: "1", label: "Yes", isSelected: true))
        #expect(choices[1].label == "Yes, and don't ask again for make commands in /work/app")
        #expect(choices[2].label == "No, and tell Claude what to do differently (esc)")
        #expect(!choices[2].isSelected)
    }

    @Test func claudeCodeOpenPrompt() {
        let choices = ChoiceParser.choices(in: Self.claudeOpen)
        #expect(choices.map(\.label) == ["Yes", "Yes, allow all edits during this session (shift+tab)",
                                          "No, and tell Claude what to do differently (esc)"])
    }

    @Test func codexPrompt() {
        let choices = ChoiceParser.choices(in: Self.codex)
        #expect(choices.map(\.key) == ["1", "2", "3"])
        #expect(choices[0] == AgentChoice(key: "1", label: "Yes, proceed (y)", isSelected: true))
    }

    @Test func cursorOnALaterChoice() {
        let text = "  1. Yes\n❯ 2. No"
        #expect(ChoiceParser.choices(in: text).map(\.isSelected) == [false, true])
    }

    @Test func aWrappedLabelKeepsTheRun() {
        let text = """
        ❯ 1. Yes
          2. Yes, and don't ask again for commands like this one in
             this project
          3. No
        """
        #expect(ChoiceParser.choices(in: text).map(\.key) == ["1", "2", "3"])
    }

    @Test func aNumberedListInOutputIsNotAPrompt() {
        let text = """
        Plan:
        1. Read the config
        2. Write the tests
        3. Ship it
        """
        #expect(ChoiceParser.choices(in: text).isEmpty)
    }

    @Test func theLastPromptWins() {
        let text = Self.codex + "\n\n" + "❯ 1. Approve\n  2. Reject"
        #expect(ChoiceParser.choices(in: text).map(\.label) == ["Approve", "Reject"])
    }

    @Test func runsMustStartAtOneAndCount() {
        #expect(ChoiceParser.choices(in: "❯ 2. Yes\n  3. No").isEmpty)
        #expect(ChoiceParser.choices(in: "❯ 1. Yes\n  3. No").isEmpty)
        #expect(ChoiceParser.choices(in: "❯ 1. Yes").isEmpty)
    }

    @Test func plainQuestionsHaveNoChoices() {
        #expect(ChoiceParser.choices(in: "Which database should I use for this?\n> ").isEmpty)
        #expect(ChoiceParser.choices(in: "").isEmpty)
        #expect(ChoiceParser.option("1.5 seconds") == nil)
        #expect(ChoiceParser.option("10. Ten") == nil)
    }
}
