import Foundation
import ShepherdCore

/// The pieces of starting a task in tmux that need no server: where its worktree goes, its branch
/// when none was given, `git worktree add`, and the new window's command.
enum TmuxNewTask {
    /// A name for a branch the user left empty: the kind and a random suffix, as herdr names agents.
    static func branchName(kind: String) -> String {
        let base = String(kind.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(20))
        let suffix = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return (base.isEmpty ? "task" : base) + "-" + suffix
    }

    /// Next to the repo's folder, named for the repo and the branch: `~/code/app` and `fix/login`
    /// give `~/code/app-fix-login`. A `.git` or `.bare` dir sits inside the repo's folder and a bare
    /// `app.git` is the folder itself; any other git dir (a submodule's, under its parent's `.git`)
    /// says nothing about where the code lives, so the checkout's own folder stands for the repo.
    static func folder(for checkout: GitCheckout, branch: String) -> String {
        let common = URL(fileURLWithPath: checkout.commonDir)
        let repoFolder = if common.lastPathComponent.hasPrefix(".") {
            common.deletingLastPathComponent()
        } else if common.lastPathComponent.hasSuffix(".git") {
            common
        } else {
            URL(fileURLWithPath: checkout.root)
        }
        let slug = branch.replacingOccurrences(of: "/", with: "-")
        return repoFolder.deletingLastPathComponent().appending(path: "\(checkout.repoName)-\(slug)").path
    }

    /// The new window's command: `/bin/sh` runs the agent with its args and the prompt as its first
    /// argument, each passed as is (no quoting, so any shell, any length), then replaces itself with
    /// the user's login shell, so the window stays when the agent exits. `--` keeps a prompt that
    /// starts with `-` from reading as a flag.
    static func command(kind: String, args: [String], prompt: String) -> [String] {
        let prompt = prompt.isEmpty ? [] : prompt.hasPrefix("-") ? ["--", prompt] : [prompt]
        return ["/bin/sh", "-c", "\"$@\"; exec \"${SHELL:-/bin/sh}\" -l", "sh", kind] + args + prompt
    }

    /// `git worktree add -b <branch> <folder>` from `checkout`, so the branch starts at its HEAD.
    /// Blocks until git exits, so call it off the main actor. A failure says what git said, and that
    /// the worktree is there when git made it before failing (a hook that failed after checkout).
    static func addWorktree(git: String, checkout: String, branch: String, folder: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-C", checkout, "worktree", "add", "-b", branch, folder]
        // An app started from Finder has a short PATH; git's hooks and filters (LFS) need the user's tools.
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"].filter { !path.contains($0) } + [path]).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw AgentSourceError.failed("git did not run: \(error.localizedDescription)")
        }
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        // git prints progress first; the reason is its last line.
        let message = String(decoding: errors, as: UTF8.self).split(whereSeparator: \.isNewline).last
            .map(String.init) ?? "exited with \(process.terminationStatus)"
        let left = FileManager.default.fileExists(atPath: folder) ? " (worktree \(branch) was left at \(folder))" : ""
        throw AgentSourceError.failed("git: \(message)\(left)")
    }

    /// The `git` binary: the first on `PATH`, else where Homebrew and the system put it.
    static func locateGit(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (path + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]).lazy.map { $0 + "/git" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
