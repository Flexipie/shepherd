import Foundation

/// `report`: an agent states its own status. Pure apart from the spool it writes to, so the whole
/// command runs in tests with a temporary spool.
public enum ReportCLI {
    public static let usage = """
        usage: report --status <working|blocked|done|idle|closed> [--message <text>] [--question <text>]
                      [--agent <id>] [--kind <kind>] [--from-hook]
        """

    /// The exit code and the text for the caller to print: stdout on 0, stderr otherwise.
    public struct Outcome: Sendable, Equatable {
        public let exitCode: Int32
        public let output: String
    }

    /// `arguments` are the words after the program name, starting with `report`. `stdin` is read
    /// only with `--from-hook`. Never echoes a report's contents.
    public static func run(arguments: [String], stdin: () -> Data, environment: [String: String],
                           cwd: String, now: Date = Date()) -> Outcome {
        guard arguments.first == "report" else {
            return Outcome(exitCode: 2, output: "\(usage)\n\(InstallCLI.usage)")
        }
        let options: Options
        do {
            options = try Options.parse(Array(arguments.dropFirst()))
        } catch let error as UsageError {
            return Outcome(exitCode: 2, output: "\(error.message)\n\(usage)")
        } catch {
            return Outcome(exitCode: 2, output: usage)
        }

        // `parse` makes sure of this; the guard only gives the type.
        guard let status = options.status else { return Outcome(exitCode: 2, output: usage) }

        var hook = HookInput()
        if options.fromHook {
            guard let parsed = HookInput(data: stdin()) else {
                return Outcome(exitCode: 2, output: "--from-hook needs one JSON object on stdin")
            }
            hook = parsed
        }

        let identity = ReportIdentity.resolve(agent: options.agent, session: hook.session, cwd: hook.cwd ?? cwd,
                                              environment: environment)
        let spool = ReportSpool(directory: ReportSpool.directory(environment: environment))
        do {
            if status == .closed {
                try spool.remove(agent: identity.key)
            } else {
                let report = ReportFile(agent: identity.key, status: status,
                                        message: options.message ?? hook.message,
                                        question: options.question, kind: options.kind,
                                        cwd: hook.cwd ?? cwd, updatedAt: now)
                try spool.write(report)
            }
        } catch {
            return Outcome(exitCode: 1, output: "could not write the report to \(spool.directory.path): \(error.localizedDescription)")
        }
        return Outcome(exitCode: 0, output: "")
    }

    struct UsageError: Error {
        let message: String
    }

    struct Options: Equatable {
        var status: ReportFile.Status?
        var message: String?
        var question: String?
        var agent: String?
        var kind: String?
        var fromHook = false

        /// `--name value` and `--name=value`. The last of a repeated flag wins.
        static func parse(_ arguments: [String]) throws -> Options {
            var options = Options()
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                index += 1
                guard argument.hasPrefix("--") else { throw UsageError(message: "unexpected argument \(argument)") }
                var name = argument
                var inline: String?
                if let equals = argument.firstIndex(of: "=") {
                    name = String(argument[..<equals])
                    inline = String(argument[argument.index(after: equals)...])
                }
                if name == "--from-hook" {
                    guard inline == nil else { throw UsageError(message: "--from-hook takes no value") }
                    options.fromHook = true
                    continue
                }
                let value: String
                if let inline {
                    value = inline
                } else {
                    guard index < arguments.count else { throw UsageError(message: "\(name) needs a value") }
                    value = arguments[index]
                    index += 1
                }
                switch name {
                case "--status":
                    guard let status = ReportFile.Status(rawValue: value) else {
                        throw UsageError(message: "unknown status \(value)")
                    }
                    options.status = status
                case "--message": options.message = clean(value)
                case "--question": options.question = clean(value)
                case "--agent": options.agent = clean(value)
                case "--kind": options.kind = clean(value)
                default: throw UsageError(message: "unknown option \(name)")
                }
            }
            guard options.status != nil else { throw UsageError(message: "--status is required") }
            return options
        }

        /// Trimmed; an empty value counts as none.
        private static func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

/// The fields of a Claude Code hook's JSON that a report uses. Read leniently: unknown keys are
/// ignored and a field of the wrong type counts as missing.
struct HookInput: Equatable {
    var session: String?
    var cwd: String?
    var message: String?

    init() {}

    /// nil when the data is not a JSON object.
    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        session = object["session_id"] as? String
        cwd = object["cwd"] as? String
        // Notification carries `message`; Stop carries the last assistant reply.
        let text = (object["message"] as? String) ?? (object["last_assistant_message"] as? String)
        message = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
