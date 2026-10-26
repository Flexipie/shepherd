import Foundation

/// The git checkout a folder is in, read from the `.git` entries on disk with no `git` process.
/// Every checkout of one repo (its main checkout and its linked worktrees) shares the repo's
/// common git dir, so that dir is the repo's key.
public struct GitCheckout: Sendable, Equatable, Hashable {
    /// The checkout's top folder: the one holding `.git`.
    public let root: String
    /// The repo's common git dir, the same for every checkout of the repo.
    public let commonDir: String
    /// False for the repo's main checkout.
    public let isLinked: Bool

    public init(root: String, commonDir: String, isLinked: Bool) {
        self.root = root
        self.commonDir = commonDir
        self.isLinked = isLinked
    }

    /// The repo's name: the main checkout's folder, a bare repo's folder without `.git`, or the
    /// folder holding a hidden bare repo (the `repo/.bare` layout).
    public var repoName: String {
        let dir = URL(fileURLWithPath: commonDir)
        let name = dir.lastPathComponent
        if name.hasPrefix(".") { return dir.deletingLastPathComponent().lastPathComponent }
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }

    public var repo: HerdRepo {
        HerdRepo(key: commonDir, name: repoName, isLinkedCheckout: isLinked)
    }

    /// The checkout holding `path`, or nil outside git. Walks up from `path` to the first `.git`:
    /// a folder is a main checkout's git dir; a file says `gitdir: <dir>`, and that dir's `commondir`
    /// names the repo's git dir for a linked worktree. A submodule's gitdir has no `commondir`, so it
    /// is its own repo. The root keeps `path`'s spelling; the key is the real path, so one repo
    /// reached two ways (such as `/tmp` and `/private/tmp`) has one key.
    public static func containing(_ path: String) -> GitCheckout? {
        guard !path.isEmpty else { return nil }
        let manager = FileManager.default
        var folder = URL(fileURLWithPath: path).standardized
        while true {
            let dotGit = folder.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return GitCheckout(root: folder.path, commonDir: real(dotGit), isLinked: false)
                }
                return linked(root: folder, dotGit: dotGit)
            }
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { return nil }
            folder = parent
        }
    }

    private static func linked(root: URL, dotGit: URL) -> GitCheckout? {
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = resolve(target, against: root)
        guard let common = try? String(contentsOf: gitDir.appending(path: "commondir"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty else {
            return GitCheckout(root: root.path, commonDir: real(gitDir), isLinked: false)
        }
        return GitCheckout(root: root.path, commonDir: real(resolve(common, against: gitDir)), isLinked: true)
    }

    /// `path` as an absolute URL, relative paths taken from `base`.
    private static func resolve(_ path: String, against base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appending(path: path)).standardized
    }

    /// The real path, with every symlink followed (unlike `resolvingSymlinksInPath`, which drops
    /// `/private`), or the path as given when it does not exist.
    private static func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
