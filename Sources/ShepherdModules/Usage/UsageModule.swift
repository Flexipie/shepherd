import Foundation
import Observation
import ShepherdCore

/// Plan usage for the user's coding agent accounts, as a panel section with one card per
/// account, on the Gadgets tab. It reads only while a panel shows that tab: once on showing it
/// when the last report is missing or past its `expiresAt`, and again at that time if it still
/// shows. Otherwise nothing runs: no timer and no request. With no reader in the context it has
/// no section.
@MainActor
@Observable
public final class UsageModule: ShepherdModule {
    public static let id = "usage"

    private(set) var report: UsageReport?
    private(set) var problem: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var isReading = false
    /// When the last report goes out of date.
    @ObservationIgnored private(set) var refreshAt: Date?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    /// Waits this long past `expiresAt`, so the reader has time to fetch newer data.
    @ObservationIgnored var grace: TimeInterval = 2
    /// How long a report without an `expiresAt` in the future, or an error, lasts.
    @ObservationIgnored var fallbackLifetime: TimeInterval = 300
    @ObservationIgnored var errorLifetime: TimeInterval = 60

    public init(context: ModuleContext) {
        self.context = context
        watchVisibility()
    }

    public var panel: PanelSection? {
        guard context.usage != nil else { return nil }
        var items = (report?.providers ?? []).map(PanelItem.usage)
        let notices = [problem].compactMap { $0 } + (report?.problems ?? [])
        items.insert(contentsOf: notices.map(PanelItem.notice), at: 0)
        let empty = report == nil && problem == nil ? "Reading usage…" : "No accounts in OpenUsage"
        return PanelSection(id: Self.id, title: "Usage", items: items, emptyText: empty, tab: .gadgets)
    }

    private func watchVisibility() {
        let visible = withObservationTracking {
            context.presence.isShowing(.gadgets)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchVisibility() }
        }
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            if refreshAt.map({ Date() >= $0 }) ?? true { read() } else { schedule() }
        } else {
            scheduled?.cancel()
            scheduled = nil
        }
    }

    private func read() {
        guard let reader = context.usage, !isReading else { return }
        isReading = true
        Task { @MainActor in
            let now: Date
            do {
                let report = try await reader.read()
                now = Date()
                self.report = report
                problem = nil
                refreshAt = Self.refreshDate(report, readAt: now, fallback: fallbackLifetime).addingTimeInterval(grace)
            } catch {
                now = Date()
                report = nil
                problem = (error as? LocalizedError)?.errorDescription ?? "Could not read usage: \(error)"
                refreshAt = now.addingTimeInterval(errorLifetime)
            }
            isReading = false
            if context.presence.isShowing(.gadgets) { schedule() }
        }
    }

    /// One read at `refreshAt`, while the Gadgets tab stays shown.
    private func schedule() {
        scheduled?.cancel()
        guard let refreshAt else { return }
        let delay = max(0, refreshAt.timeIntervalSinceNow)
        scheduled = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Presence, not `isVisible`: a close may not have reached `watchVisibility` yet.
            guard !Task.isCancelled, let self, self.context.presence.isShowing(.gadgets) else { return }
            self.scheduled = nil
            self.read()
        }
    }

    /// The earliest `expiresAt` still ahead. A stale account's may be long past; it does not
    /// count, or every opening would read.
    static func refreshDate(_ report: UsageReport, readAt: Date, fallback: TimeInterval) -> Date {
        report.providers.compactMap(\.expiresAt).filter { $0 > readAt }.min() ?? readAt.addingTimeInterval(fallback)
    }
}
