import Foundation
import Testing
@testable import ShellPlugins
@testable import ShepherdCore

@Suite struct ProcessPluginRunnerTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "shepherd-plugin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "echo \"$1 from $(basename \"$PWD\") as $SHEPHERD_AGENT_NAME\"\necho oops >&2\nexit ${2:-0}\n"
            .write(to: folder.appending(path: "hello.sh"), atomically: true, encoding: .utf8)
    }

    @Test func runsFromThePluginFolderWithItsEnvironment() async throws {
        let result = try await ProcessPluginRunner().run(["sh", "hello.sh", "hi"], in: folder,
                                                         environment: ["SHEPHERD_AGENT_NAME": "claude"], timeout: .seconds(5))
        #expect(result.status == 0)
        #expect(result.stdout == "hi from \(folder.lastPathComponent) as claude\n")
        #expect(result.stderr == "oops\n")
    }

    @Test func aFailureIsAResult() async throws {
        let result = try await ProcessPluginRunner().run(["sh", "hello.sh", "hi", "3"], in: folder, environment: [:], timeout: .seconds(5))
        #expect(result.status == 3)
        #expect(PluginHost.failure(result) == "exited with 3: oops")
    }

    @Test func pastTheTimeoutItIsStopped() async throws {
        let start = Date()
        await #expect(throws: ProcessPluginRunner.TimedOut.self) {
            _ = try await ProcessPluginRunner().run(["sleep", "30"], in: folder, environment: [:], timeout: .milliseconds(300))
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func outputIsCapped() async throws {
        var runner = ProcessPluginRunner()
        runner.outputLimit = 1000
        let result = try await runner.run(["sh", "-c", "yes | head -c 100000"], in: folder, environment: [:], timeout: .seconds(5))
        #expect(result.status == 0)
        #expect(result.stdout.utf8.count == 1000)
    }
}
