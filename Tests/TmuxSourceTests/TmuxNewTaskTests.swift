import Foundation
import ShepherdCore
import Testing
import TmuxKit
import TmuxTestSupport
@testable import TmuxSource

/// Starting a task: a worktree next to the repo, a window on the project's server, and the agent's
/// command typed into its shell.
extension TmuxSourceTests {
    /// A repo with one commit at `folder/repo`, and a `claude` in `folder/bin` that writes its
    /// arguments to `folder/args`, one per line, then shows an idle screen.
    func repoAndRecordingClaude(in folder: URL) throws -> (repo: URL, bin: URL) {
        let repo = folder.appending(path: "repo")
        let bin = folder.appending(path: "bin")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try git(["init", "-q"], in: repo)
        try git(["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "--allow-empty", "-m", "init"], in: repo)
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(folder.path)/args'\ncat <<'SCREEN'\n\(Self.idle)\nSCREEN\nsleep 120\n"
        let file = bin.appending(path: "claude")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return (repo, bin)
    }

    func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(TmuxNewTask.locateGit()))
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func aNewTaskMakesAWorktreeAndStartsItsAgentInANewWindow() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (repo, bin) = try repoAndRecordingClaude(in: folder)
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "cd '\(repo.path)' && exec '\(bin.path)/claude'")
        defer { withExtendedLifetime(tmux) {} }
        // The new window's command finds the fake claude on the server's PATH.
        try PrivateTmux.run(binary, ["-S", tmux.socket, "set-environment", "-g", "PATH", "\(bin.path):/usr/bin:/bin"])
        // The pane changes folder before the first agent runs; a scan before that would see the wrong one.
        let args = folder.appending(path: "args")
        #expect(tmux.until { FileManager.default.fileExists(atPath: args.path) })
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }
        await until { store.agents.count == 1 }
        let project = try #require(store.projects.first)
        #expect(project.path == repo.path)
        #expect(store.canStartTask(in: project.id))

        let agent = try await store.startTask(
            NewTask(project: project.id, branch: "fix/login", kind: "claude", prompt: Self.longPrompt),
            args: ["--model", "a b"])
        // Before any scan lists it, the new agent can already be read, as its stage does at once.
        _ = try await store.read(agent, lines: 5)

        #expect(agent.source == "tmux")
        #expect(agent.local.hasPrefix("tmux:\(tmux.socket):%"))
        let worktree = folder.appending(path: "repo-fix-login")
        #expect(FileManager.default.fileExists(atPath: worktree.appending(path: ".git").path))
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: ".git/refs/heads/fix/login").path))
        await until { (try? String(contentsOf: args, encoding: .utf8)) == "--model\na b\n\(Self.longPrompt)\n" }
        let recorded = try String(contentsOf: args, encoding: .utf8)
        #expect(recorded == "--model\na b\n\(Self.longPrompt)\n")
        await until { store.agents.contains { $0.id == agent } }
        let started = try #require(store.agents.first { $0.id == agent })
        #expect(started.cwd == worktree.path)
        #expect(started.kind == "claude")
    }

    /// Past the terminal's 1 KB line limit, with a quote, a tab and a backslash: it must reach the agent whole.
    static let longPrompt = "it's broken:\tsee \\n " + String(repeating: "the login page loops. ", count: 80)

    @Test func theWorktreeGoesNextToTheRepoFolder() {
        let plain = GitCheckout(root: "/code/app", commonDir: "/code/app/.git", isLinked: false)
        #expect(TmuxNewTask.folder(for: plain, branch: "fix/login") == "/code/app-fix-login")
        let hidden = GitCheckout(root: "/code/app/main", commonDir: "/code/app/.bare", isLinked: true)
        #expect(TmuxNewTask.folder(for: hidden, branch: "x") == "/code/app-x")
        let bare = GitCheckout(root: "/code/app-wt", commonDir: "/code/app.git", isLinked: true)
        #expect(TmuxNewTask.folder(for: bare, branch: "x") == "/code/app-x")
        let submodule = GitCheckout(root: "/code/app/lib", commonDir: "/code/app/.git/modules/lib", isLinked: false)
        #expect(TmuxNewTask.folder(for: submodule, branch: "x") == "/code/app/lib-x")
    }
}
