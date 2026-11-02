import Foundation

/// A manifest's `gadget`: a command that prints a card for the Gadgets tab, run every `every`
/// seconds while a surface shows that tab.
public struct PluginGadget: Sendable, Equatable {
    /// The card's title when the output names none.
    public let title: String?
    /// The program and its arguments, run from the plugin's folder.
    public let command: [String]
    /// Seconds between runs.
    public let every: Double

    public static let defaultEvery: Double = 60
    /// Shorter intervals are raised to this, so a typo cannot spin a process.
    public static let minimumEvery: Double = 2
    /// Longer ones are lowered to this, so a huge number cannot overflow a `Duration`.
    public static let maximumEvery: Double = 86_400

    public init(title: String? = nil, command: [String], every: Double = PluginGadget.defaultEvery) {
        self.title = title
        self.command = command
        self.every = min(max(every, Self.minimumEvery), Self.maximumEvery)
    }

    /// Reads a manifest's `gadget`, or nil with a problem when it cannot be used.
    static func read(_ value: ConfigValue?, at path: String, problems: inout [String]) -> PluginGadget? {
        guard let value else { return nil }
        guard case .table(let table) = value, let command = table["command"].flatMap(PluginAction.command) else {
            problems.append("\(path) needs a command (a list of strings)")
            return nil
        }
        let title = if case .string(let title)? = table["title"], !title.isEmpty { title } else { String?.none }
        var every = defaultEvery
        if let raw = table["every"] {
            if case .number(let seconds) = raw, seconds > 0 { every = seconds } else { problems.append("\(path).every must be a number of seconds") }
        }
        return PluginGadget(title: title, command: command, every: every)
    }

    /// The card a run printed: `{"title": ..., "detail": ..., "meters": [...], "lines": [...]}`,
    /// each meter `{"label": ..., "fraction": 0...1, "text": ...}` (text defaults to the percent).
    /// Throws a message when the output is not such an object or a meter lacks its label or fraction.
    public static func card(from stdout: String, id: String, title fallback: String) throws(ConfigProblem) -> GadgetCard {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .table(let table)? = try? JSONDecoder().decode(ConfigValue.self, from: Data(trimmed.utf8)) else {
            throw ConfigProblem("must print a JSON object with a title, meters and lines")
        }
        let title = if case .string(let title)? = table["title"], !title.isEmpty { title } else { fallback }
        let detail = if case .string(let detail)? = table["detail"], !detail.isEmpty { detail } else { String?.none }
        var meters: [GadgetMeter] = []
        if case .array(let items)? = table["meters"] {
            for (index, item) in items.enumerated() {
                guard case .table(let meter) = item, case .string(let label)? = meter["label"],
                      case .number(let fraction)? = meter["fraction"] else {
                    throw ConfigProblem("meters[\(index)] needs a label and a fraction (a number from 0 to 1)")
                }
                let text = if case .string(let text)? = meter["text"] { text } else { "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%" }
                meters.append(GadgetMeter(id: "\(index)", label: label, fraction: fraction, valueText: text))
            }
        }
        var lines: [String] = []
        if case .array(let items)? = table["lines"] {
            lines = items.compactMap { item in if case .string(let line) = item { line } else { nil } }
        }
        return GadgetCard(id: id, title: title, detail: detail, meters: meters, lines: lines)
    }
}
