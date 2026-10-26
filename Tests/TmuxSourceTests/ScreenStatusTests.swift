import ShepherdCore
import Testing
@testable import TmuxSource

/// Screens shaped like the agents' own, with paths and text made generic. The shapes were checked
/// on Claude Code 2.1.299 and Codex 0.162.1.
@Suite struct ScreenStatusTests {
    static let claudeIdle = """
     ▐▛███▛█   Claude Code v2.1.299
    ▝▜██████▀  Opus 5.5 · Claude Team
     ▝▝   ▝▝   ~/work/app

    ────────────────────────────────────────────────────────────
    ❯ Try "write a test for the parser"
    ────────────────────────────────────────────────────────────
      ⏵⏵ auto mode on (shift+tab to cycle) · ← 3 agents
    """

    static let claudeWorking = """
    ⏺ Reading the parser now.

    ✻ Churning… (5s · esc to interrupt)
    ────────────────────────────────────────────────────────────
    ❯
    ────────────────────────────────────────────────────────────
      ⏵⏵ auto mode on · esc to interrupt · ← 3 agents
    """

    static let claudeApproval = """
    ⏺ Bash(make test)

     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and don't ask again for make commands in /work/app
       3. No, and tell Claude what to do differently (esc)
    """

    static let claudeTrust = """
     Accessing workspace:

     /work/app

     Quick safety check: Is this a project you created or one you trust?

     Security guide

     ❯ No, exit
       Yes, I trust this folder

     Enter to confirm · Esc to cancel
    """

    static let codexIdle = """
    ╭──────────────────────────────────────────────╮
    │ >_ OpenAI Codex (v0.162.1)                   │
    ╰──────────────────────────────────────────────╯
      ~/work/app
    › Ask Codex to do anything
      GPT-6.1-Sol medium · ~/work/app
      ← for agents · ? for shortcuts                       ⚠ 3 warnings
    """

    static let codexWorking = """
    › Run the tests
    • I’ll run the command, then reply.
    • Working (5s • esc to interrupt) · 1 background terminal running
    › Ask Codex to do anything
      GPT-6.1-Sol medium · ~/work/app · ⠇
      ← for agents · ? for shortcuts
    """

    static let codexUpdate = """
      Update available · 0.162.1 → 0.163.0
      Release notes: https://example.com/releases
    › 1. Update now (runs `brew upgrade --cask codex`)
      2. Skip
      3. Skip until next version
      enter continue · esc skip
    """

    @Test func claudeIdleInputIsIdle() {
        #expect(ScreenStatus.status(kind: "claude", screen: Self.claudeIdle) == .idle)
    }

    @Test func theTurnHintIsWorkingEvenWithTheInputLineShowing() {
        #expect(ScreenStatus.status(kind: "claude", screen: Self.claudeWorking) == .working)
        #expect(ScreenStatus.status(kind: "codex", screen: Self.codexWorking) == .working)
    }

    @Test func anApprovalPromptIsBlockedAndATrustPromptIsToo() {
        #expect(ScreenStatus.status(kind: "claude", screen: Self.claudeApproval) == .blocked)
        #expect(ScreenStatus.status(kind: "codex", screen: Self.codexUpdate) == .blocked)
    }

    @Test func aTrustPromptWithACursorIsNotIdle() {
        #expect(ScreenStatus.status(kind: "claude", screen: Self.claudeTrust) == .unknown)
    }

    @Test func codexIdleInputIsIdle() {
        #expect(ScreenStatus.status(kind: "codex", screen: Self.codexIdle) == .idle)
    }

    @Test func aScreenWithNoMarkersIsUnknown() {
        #expect(ScreenStatus.status(kind: "claude", screen: "$ ls\nREADME.md\n$ ") == .unknown)
        #expect(ScreenStatus.status(kind: "codex", screen: "") == .unknown)
    }

    @Test func aMarkerHigherUpTheTranscriptDoesNotCount() {
        let old = "I said esc to interrupt once.\n" + (1...12).map { "line \($0)" }.joined(separator: "\n")
        #expect(ScreenStatus.status(kind: "claude", screen: old) == .unknown)
    }

    @Test func aNumberedListInOutputIsNotAPrompt() {
        let list = "Steps:\n1. Read it\n2. Test it\n3. Ship it\n"
        #expect(ScreenStatus.status(kind: "claude", screen: list) == .unknown)
    }

    @Test func theAgentKindsAreClaudeAndCodex() {
        #expect(ScreenStatus.kinds == ["claude", "codex"])
    }
}
