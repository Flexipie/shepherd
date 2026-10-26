import Foundation
import TmuxKit

/// A tmux server on its own socket, for tests. The socket lives under `/private/tmp` because Unix
/// socket paths are short. The server is killed and its folder removed when the test ends.
public final class PrivateTmux: @unchecked Sendable {
    public let binary: String
    public let folder: URL
    public let socket: String
    public var client: TmuxClient { TmuxClient(binary: binary, socket: socket) }

    /// A server whose socket is `folder/s`. A folder given is used as it is, so a test can point a source at it first.
    public init(binary: String, folder: URL? = nil, command: String = "cat") throws {
        self.binary = binary
        self.folder = folder ?? URL(fileURLWithPath: "/private/tmp").appending(path: "shp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        socket = self.folder.appending(path: "s").path
        try Self.run(binary, ["-S", socket, "new-session", "-d", "-s", "w", "-x", "120", "-y", "40", "-c", self.folder.path, command])
    }

    deinit {
        _ = try? Self.run(binary, ["-S", socket, "kill-server"])
        try? FileManager.default.removeItem(at: folder)
    }

    /// Waits up to 5 s for `condition`, so a busy run does not fail on timing.
    public func until(_ condition: () throws -> Bool) rethrows -> Bool {
        for _ in 0..<500 {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    @discardableResult
    public static func run(_ binary: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["TMUX"] = nil
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
