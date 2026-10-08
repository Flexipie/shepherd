import Foundation

/// A pushed event. Shepherd treats events as invalidation, so only the kind and the ids it
/// names are decoded; the payload is ignored.
public struct HerdrEvent: Decodable, Sendable, Equatable {
    /// The event name with dots normalised to underscores. herdr sends global events as
    /// `workspace_focused` and per-pane ones as `pane.agent_status_changed`.
    public let kind: String
    public let paneID: String?
    public let workspaceID: String?

    public init(kind: String, paneID: String? = nil, workspaceID: String? = nil) {
        self.kind = Self.normalise(kind)
        self.paneID = paneID
        self.workspaceID = workspaceID
    }

    public static func normalise(_ name: String) -> String {
        name.replacingOccurrences(of: ".", with: "_")
    }

    private enum CodingKeys: String, CodingKey { case event, data }
    private enum DataKeys: String, CodingKey { case paneID = "pane_id", workspaceID = "workspace_id" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = Self.normalise(try container.decode(String.self, forKey: .event))
        let data = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        paneID = try? data?.decodeIfPresent(String.self, forKey: .paneID)
        workspaceID = try? data?.decodeIfPresent(String.self, forKey: .workspaceID)
    }
}
