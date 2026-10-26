import Testing
@testable import ReportKit

@Suite struct ReportIdentityTests {
    let tmux = ["TMUX": "/tmp/tmux-501/default,4242,0", "TMUX_PANE": "%3"]

    @Test func theFlagWinsOverEverything() {
        let identity = ReportIdentity.resolve(agent: "mine", session: "abc", cwd: "/w",
                                              environment: ["SHEPHERD_AGENT_ID": "env"].merging(tmux) { $1 })
        #expect(identity == ReportIdentity(key: "mine", method: .flag))
    }

    @Test func theEnvironmentComesNextThenTheTmuxPane() {
        let env = ["SHEPHERD_AGENT_ID": "env"].merging(tmux) { $1 }
        #expect(ReportIdentity.resolve(agent: nil, session: "abc", cwd: "/w", environment: env)
            == ReportIdentity(key: "env", method: .environment))
        #expect(ReportIdentity.resolve(agent: nil, session: "abc", cwd: "/w", environment: tmux)
            == ReportIdentity(key: "tmux:/tmp/tmux-501/default:%3", method: .tmux))
    }

    @Test func aTmuxKeyNeedsBothVariablesAndUsesOnlyTheSocketPath() {
        #expect(ReportIdentity.resolve(agent: nil, session: nil, cwd: "/w", environment: ["TMUX": "/s,1,0"])
            == ReportIdentity(key: "cwd:/w", method: .directory))
        let pane = ReportIdentity.resolve(agent: nil, session: nil, cwd: "/w", environment: ["TMUX": "/s,99,2", "TMUX_PANE": "%7"])
        #expect(pane.key == "tmux:/s:%7")
    }

    @Test func theHookSessionComesBeforeTheFolder() {
        #expect(ReportIdentity.resolve(agent: nil, session: "sess-1", cwd: "/w", environment: [:])
            == ReportIdentity(key: "session:sess-1", method: .session))
    }

    @Test func theWorkingDirectoryIsTheLastResort() {
        #expect(ReportIdentity.resolve(agent: nil, session: nil, cwd: "/w/app", environment: [:])
            == ReportIdentity(key: "cwd:/w/app", method: .directory))
    }

    @Test func emptyValuesCountAsMissing() {
        let identity = ReportIdentity.resolve(agent: "  ", session: "", cwd: "/w", environment: ["SHEPHERD_AGENT_ID": " "])
        #expect(identity.method == .directory)
    }
}
