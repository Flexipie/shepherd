import Foundation

/// Plan usage limits for the user's coding agent accounts, as a reader found them. Values only,
/// already worded, so modules and views never see a reader's own format.
public struct UsageReport: Sendable, Equatable {
    public let providers: [UsageProvider]
    /// Things the reader could not attach to a provider.
    public let problems: [String]

    public init(providers: [UsageProvider], problems: [String] = []) {
        self.providers = providers
        self.problems = problems
    }
}

/// One account: "Claude, Max 5x" with its session and weekly meters.
public struct UsageProvider: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let plan: String?
    /// The reader's data for it is old, such as after a failed refresh.
    public let isStale: Bool
    public let meters: [UsageMeter]
    /// Short lines under the meters: balances, errors.
    public let notes: [String]
    /// When the reader expects newer data; nil when it does not say.
    public let expiresAt: Date?

    public init(id: String, name: String, plan: String? = nil, isStale: Bool = false, meters: [UsageMeter],
                notes: [String] = [], expiresAt: Date? = nil) {
        self.id = id
        self.name = name
        self.plan = plan
        self.isStale = isStale
        self.meters = meters
        self.notes = notes
        self.expiresAt = expiresAt
    }
}

/// One limit, as a bar: "Session, 42%, resets at 14:00".
public struct UsageMeter: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// How much of the limit is used, 0...1.
    public let fraction: Double
    /// "42%", "$12 of $50".
    public let valueText: String
    public let resetsAt: Date?

    public init(id: String, label: String, fraction: Double, valueText: String, resetsAt: Date? = nil) {
        self.id = id
        self.label = label
        self.fraction = min(max(fraction, 0), 1)
        self.valueText = valueText
        self.resetsAt = resetsAt
    }
}

/// Reads a usage report once per call. The app's reader lives in its own target, so modules
/// decide when to read and never do the I/O themselves. A thrown error's description is shown
/// to the user.
@MainActor
public protocol UsageReader: AnyObject {
    func read() async throws -> UsageReport
}
