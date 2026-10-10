import Foundation

/// What Shepherd subscribes to: every lifecycle event type, plus agent status changes for each
/// pane with an agent. herdr requires a `pane_id` for agent status subscriptions and rejects the
/// whole request if any named pane is gone, so the pane set always comes from a recent snapshot.
/// Each named pane costs herdr a check every 100 ms, so plain shells are left out; one that gains
/// an agent sends `pane.agent_detected`, which brings a new snapshot and a new set.
public struct SubscriptionSet: Sendable, Hashable {
    public var paneIDs: Set<String>

    public init(paneIDs: Set<String> = []) {
        self.paneIDs = paneIDs
    }

    /// Only lifecycle events. Cannot fail on a missing pane.
    public static let globalOnly = SubscriptionSet()

    public static let globalTypes = [
        "workspace.created", "workspace.updated", "workspace.metadata_updated", "workspace.renamed",
        "workspace.moved", "workspace.reordered", "workspace.closed", "workspace.focused",
        "worktree.created", "worktree.opened", "worktree.removed",
        "tab.created", "tab.closed", "tab.focused", "tab.renamed", "tab.moved",
        "pane.created", "pane.closed", "pane.updated", "pane.focused", "pane.moved", "pane.exited",
        "pane.agent_detected",
    ]

    package var params: SubscribeParams {
        let globals = Self.globalTypes.map { SubscribeParams.Entry(type: $0, paneID: nil) }
        let panes = paneIDs.sorted().map { SubscribeParams.Entry(type: "pane.agent_status_changed", paneID: $0) }
        return SubscribeParams(subscriptions: globals + panes)
    }
}

package struct SubscribeParams: Encodable, Sendable {
    package struct Entry: Encodable, Sendable {
        let type: String
        let paneID: String?

        enum CodingKeys: String, CodingKey { case type, paneID = "pane_id" }
    }

    let subscriptions: [Entry]
}
