import Foundation
import ShepherdCore

/// Runs plugin commands as processes: through `/usr/bin/env`, so a bare name is looked up on
/// `PATH`, from the plugin's folder, with the app's environment plus Homebrew's directories (an
/// app launched from Finder has a short `PATH`) and the plugin's variables. Output past
/// `outputLimit` is dropped. Past the timeout the process is terminated, then killed.
public struct ProcessPluginRunner: PluginRunner {
    public var outputLimit = 256 * 1024

    public init() {}

    public struct TimedOut: Error, CustomStringConvertible {
        public let seconds: Int
        public var description: String { "did not finish within \(seconds) s" }
    }

    public func run(_ command: [String], in folder: URL, environment: [String: String], timeout: Duration) async throws -> PluginRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"].filter { !path.contains($0) } + [path]).joined(separator: ":")
        env.merge(environment) { _, new in new }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let limit = outputLimit
        // Read both pipes while the process runs, so a chatty one cannot fill a pipe and stall.
        let out = Task.detached { Self.read(stdout.fileHandleForReading, limit: limit) }
        let err = Task.detached { Self.read(stderr.fileHandleForReading, limit: limit) }
        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        let seconds = Int(timeout.components.seconds)
        let status: Int32? = await withTaskGroup(of: Int32?.self) { group in
            group.addTask { for await status in exited { return status }; return nil }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let status else {
            process.terminate()
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw TimedOut(seconds: seconds)
        }
        return PluginRunResult(status: status, stdout: await out.value, stderr: await err.value)
    }

    private static func read(_ handle: FileHandle, limit: Int) -> String {
        var data = Data()
        while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
        }
        return String(decoding: data, as: UTF8.self)
    }
}
