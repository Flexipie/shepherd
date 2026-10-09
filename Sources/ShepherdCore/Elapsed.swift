import Foundation

/// Short, honest durations: "4m" when Shepherd saw the change, "4m+" when it only knows the
/// state began no later than when it looked.
public enum Elapsed {
    public static func short(_ since: Since?, now: Date = Date()) -> String? {
        guard let since else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(since.date)))
        let text = switch seconds {
        case ..<60: "now"
        case ..<3600: "\(seconds / 60)m"
        case ..<86_400: "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        default: "\(seconds / 86_400)d"
        }
        return since.precision == .noLaterThan && seconds >= 60 ? text + "+" : text
    }

    /// The same duration for VoiceOver: "4 minutes", "at least 1 hour 5 minutes".
    public static func spoken(_ since: Since?, now: Date = Date()) -> String? {
        guard let since else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(since.date)))
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        let text = switch seconds {
        case ..<60: "just now"
        case ..<3600: unit(seconds / 60, "minute")
        case ..<86_400: seconds % 3600 < 60 ? unit(seconds / 3600, "hour")
            : unit(seconds / 3600, "hour") + " " + unit(seconds % 3600 / 60, "minute")
        default: unit(seconds / 86_400, "day")
        }
        return since.precision == .noLaterThan && seconds >= 60 ? "at least " + text : text
    }
}
