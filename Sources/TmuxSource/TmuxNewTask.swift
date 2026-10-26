import Foundation
import ShepherdCore

/// The pieces of starting a task in tmux that need no server: where its worktree goes, its branch
/// when none was given, `git worktree add`, and the line typed into the new window's shell.
enum TmuxNewTask {
    /// A name for a branch the user left empty: the kind and a random suffix, as herdr names agents.
    static func branchName(kind: String) -> String {
        let base = String(kind.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(20))
        let suffix = String(UInt32.random(in: 0..<UInt32.max), radix: 36)
        return (base.isEmpty ? "task" : base) + "-" + suffix
    }

    /// Next to the repo's folder, named for the repo and the branch: `~/code/app` and `fix/login`
    /// give `~/code/app-fix-login`. A `.git` or `.bare` dir sits inside the repo's folder; a bare
    /// `app.git` is the folder itself.
    static func folder(for checkout: GitCheckout, branch: String) -> String {
        let common = URL(fileURLWithPath: checkout.commonDir)
        let repoFolder = common.lastPathComponent.hasPrefix(".") ? common.deletingLastPathComponent() : common
        let slug = branch.replacingOccurrences(of: "/", with: "-")
        return repoFolder.deletingLastPathComponent().appending(path: "\(checkout.repoName)-\(slug)").path
    }

    /// The agent's command, its args and the prompt as its first argument, quoted for a POSIX
    /// shell. Plain words stay bare, so an alias named for the kind still applies.
    static func commandLine(kind: String, args: [String], prompt: String) -> String {
        let words = [kind] + args + (prompt.isEmpty ? [] : [prompt])
        return words.map(quoted).joined(separator: " ")
    }

    static func quoted(_ word: String) -> String {
        let plain = !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0)) }
        return plain ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `git worktree add -b <branch> <folder>` from `checkout`, so the branch starts at its HEAD.
    /// Blocks until git exits, so call it off the main actor. A failure says what git said.
    static func addWorktree(git: String, checkout: String, branch: String, folder: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-C", checkout, "worktree", "add", "-b", branch, folder]
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
        throw AgentSourceError.failed("git: \(message)")
    }

    /// The `git` binary: the first on `PATH`, else where Homebrew and the system put it.
    static func locateGit(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (path + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]).lazy.map { $0 + "/git" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
