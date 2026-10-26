import Darwin
import Foundation
import ReportKit

let arguments = Array(CommandLine.arguments.dropFirst())
let outcome: ReportCLI.Outcome
if arguments.first == "install" || arguments.first == "uninstall" {
    outcome = InstallCLI.run(
        arguments: arguments,
        environment: ProcessInfo.processInfo.environment,
        show: { print($0, terminator: ""); fflush(stdout) },
        confirm: {
            guard isatty(STDIN_FILENO) != 0 else { return nil }
            // On stderr, so a pager on stdout does not swallow the question.
            FileHandle.standardError.write(Data("Write this change? [y/N] ".utf8))
            return ["y", "yes"].contains(readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "")
        })
} else {
    outcome = ReportCLI.run(
        arguments: arguments,
        stdin: { FileHandle.standardInput.readDataToEndOfFile() },
        environment: ProcessInfo.processInfo.environment,
        cwd: FileManager.default.currentDirectoryPath)
}
if !outcome.output.isEmpty {
    FileHandle.standardError.write(Data((outcome.output + "\n").utf8))
}
exit(outcome.exitCode)
