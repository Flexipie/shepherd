import Foundation
import HerdrKit

/// Short, honest durations: "4m" when Shepherd saw the change, "4m+" when it only knows the
/// state began no later than when it looked.
public enum Elapsed {
    public static func short(_ since: StateSince?, now: Date = Date()) -> String? {
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
}
