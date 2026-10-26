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
        // New windows get a plain shell that finds the fake claude. The default is a login shell, whose
        // profile would reset PATH and find a real one.
        try PrivateTmux.run(binary, ["-S", tmux.socket, "set-option", "-g", "default-command",
                                     "env PATH='\(bin.path):/usr/bin:/bin' /bin/sh"])
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
            NewTask(project: project.id, branch: "fix/login", kind: "claude", prompt: "it's broken"),
            args: ["--model", "a b"])

        #expect(agent.source == "tmux")
        #expect(agent.local.hasPrefix("tmux:\(tmux.socket):%"))
        let worktree = folder.appending(path: "repo-fix-login")
        #expect(FileManager.default.fileExists(atPath: worktree.appending(path: ".git").path))
        #expect(FileManager.default.fileExists(atPath: repo.appending(path: ".git/refs/heads/fix/login").path))
        await until { (try? String(contentsOf: args, encoding: .utf8)) == "--model\na b\nit's broken\n" }
        let recorded = try String(contentsOf: args, encoding: .utf8)
        #expect(recorded == "--model\na b\nit's broken\n")
        await until { store.agents.contains { $0.id == agent } }
        let started = try #require(store.agents.first { $0.id == agent })
        #expect(started.cwd == worktree.path)
        #expect(started.kind == "claude")
    }

    @Test func aProjectOutsideGitCannotStartATask() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        try fakeClaude(in: folder, screens: [Self.idle])
        let tmux = try PrivateTmux(binary: binary, folder: folder, command: "\(folder.path)/claude")
        defer { withExtendedLifetime(tmux) {} }
        let (store, source) = try running(folder)
        defer { Task { await source.stop() } }
        await until { store.agents.count == 1 }
        let project = try #require(store.projects.first)
        let name = folder.lastPathComponent
        await #expect(throws: AgentSourceError.failed("\(name) is not in a git repo, so there is no worktree to make")) {
            try await store.startTask(NewTask(project: project.id, kind: "claude", prompt: ""), args: [])
        }
    }

    @Test func theWorktreeGoesNextToTheRepoFolder() {
        let plain = GitCheckout(root: "/code/app", commonDir: "/code/app/.git", isLinked: false)
        #expect(TmuxNewTask.folder(for: plain, branch: "fix/login") == "/code/app-fix-login")
        let hidden = GitCheckout(root: "/code/app/main", commonDir: "/code/app/.bare", isLinked: true)
        #expect(TmuxNewTask.folder(for: hidden, branch: "x") == "/code/app-x")
        let bare = GitCheckout(root: "/code/app-wt", commonDir: "/code/app.git", isLinked: true)
        #expect(TmuxNewTask.folder(for: bare, branch: "x") == "/code/app-x")
    }

    @Test func theCommandLineQuotesOnlyWhatNeedsIt() {
        #expect(TmuxNewTask.commandLine(kind: "claude", args: ["--model", "a b"], prompt: "it's") == "claude --model 'a b' 'it'\\''s'")
        #expect(TmuxNewTask.commandLine(kind: "codex", args: [], prompt: "") == "codex")
    }
}
