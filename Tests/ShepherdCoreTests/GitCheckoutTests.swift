import Foundation
import Testing
import ShepherdCore

/// Checkouts read from real repos made with `git` in a scratch folder.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/git")))
struct GitCheckoutTests {
    func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main"] + arguments
        process.currentDirectoryURL = folder
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// A scratch folder holding a repo `app` with one commit. `/tmp` is a symlink on macOS, so the
    /// folder is given through it: the root keeps that spelling and the key is the real path.
    func repo() throws -> (scratch: URL, app: URL) {
        let scratch = URL(fileURLWithPath: "/tmp").appending(path: "shp-git-\(UUID().uuidString.prefix(8))")
        let app = scratch.appending(path: "app")
        try FileManager.default.createDirectory(at: app.appending(path: "Sources/Deep"), withIntermediateDirectories: true)
        try git(["init", "-q"], in: app)
        try git(["commit", "-q", "--allow-empty", "-m", "first"], in: app)
        return (scratch, app)
    }

    @Test func aFolderInTheMainCheckoutIsThatCheckout() throws {
        let (scratch, app) = try repo()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let checkout = try #require(GitCheckout.containing(app.appending(path: "Sources/Deep").path))
        #expect(checkout.root == app.path)
        #expect(checkout.commonDir == "/private" + app.appending(path: ".git").path)
        #expect(!checkout.isLinked)
        #expect(checkout.repo == HerdRepo(key: checkout.commonDir, name: "app", isLinkedCheckout: false))
    }

    @Test func aLinkedWorktreeSharesTheMainCheckoutsKey() throws {
        let (scratch, app) = try repo()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let tree = scratch.appending(path: "app-fix")
        try git(["worktree", "add", "-q", "-b", "fix", tree.path], in: app)
        let main = try #require(GitCheckout.containing(app.path))
        let linked = try #require(GitCheckout.containing(tree.path))
        #expect(linked.root == tree.path)
        #expect(linked.isLinked)
        #expect(linked.commonDir == main.commonDir)
        #expect(linked.repoName == "app")
    }

    @Test func aWorktreeOfABareRepoIsNamedWithoutDotGit() throws {
        let (scratch, app) = try repo()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try git(["clone", "-q", "--bare", app.path, scratch.appending(path: "lib.git").path], in: scratch)
        let tree = scratch.appending(path: "lib-main")
        try git(["worktree", "add", "-q", tree.path, "main"], in: scratch.appending(path: "lib.git"))
        let checkout = try #require(GitCheckout.containing(tree.path))
        #expect(checkout.isLinked)
        #expect(checkout.repoName == "lib")
    }

    @Test func aFolderOutsideGitHasNoCheckout() throws {
        let (scratch, _) = try repo()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(GitCheckout.containing(scratch.path) == nil)
        #expect(GitCheckout.containing("") == nil)
    }
}
