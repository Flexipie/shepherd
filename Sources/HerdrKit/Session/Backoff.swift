import Foundation

/// Retry delays after consecutive failures, capped at a minute so a missing herdr costs at most
/// one connection attempt per minute once it has been gone a while.
public enum Backoff {
    static let steps: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(5), .seconds(10), .seconds(30), .seconds(60)]

    /// The delay before attempt `failures + 1`; `failures` starts at 1.
    public static func delay(afterFailures failures: Int) -> Duration {
        steps[min(max(failures, 1), steps.count) - 1]
    }
}
