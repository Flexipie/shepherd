import Foundation
import ReportKit

let outcome = ReportCLI.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdin: { FileHandle.standardInput.readDataToEndOfFile() },
    environment: ProcessInfo.processInfo.environment,
    cwd: FileManager.default.currentDirectoryPath)
if !outcome.output.isEmpty {
    FileHandle.standardError.write(Data((outcome.output + "\n").utf8))
}
exit(outcome.exitCode)
