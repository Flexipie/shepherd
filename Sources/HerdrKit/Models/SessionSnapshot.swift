import Foundation

/// herdr's `session.snapshot`: everything Shepherd shows, read in one request. Layouts are not
/// decoded; Shepherd does not draw panes.
public struct SessionSnapshot: Sendable, Equatable, Decodable {
    public let version: String
    public let `protocol`: Int
    public let focusedWorkspaceID: String?
    public let focusedTabID: String?
    public let focusedPaneID: String?
    public let workspaces: [Workspace]
    public let tabs: [Tab]
    public let panes: [Pane]
    public let agents: [Agent]

    public init(version: String = "", protocol: Int = HerdrProtocol.tested, focusedWorkspaceID: String? = nil,
                focusedTabID: String? = nil, focusedPaneID: String? = nil, workspaces: [Workspace] = [],
                tabs: [Tab] = [], panes: [Pane] = [], agents: [Agent] = []) {
        self.version = version
        self.protocol = `protocol`
        self.focusedWorkspaceID = focusedWorkspaceID
        self.focusedTabID = focusedTabID
        self.focusedPaneID = focusedPaneID
        self.workspaces = workspaces
        self.tabs = tabs
        self.panes = panes
        self.agents = agents
    }

    public static let empty = SessionSnapshot()

    private enum CodingKeys: String, CodingKey {
        case version, `protocol`, focusedWorkspaceID = "focused_workspace_id", focusedTabID = "focused_tab_id"
        case focusedPaneID = "focused_pane_id", workspaces, tabs, panes, agents
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.lenient(.version, default: "")
        `protocol` = c.lenient(.protocol, default: 0)
        focusedWorkspaceID = c.lenient(.focusedWorkspaceID)
        focusedTabID = c.lenient(.focusedTabID)
        focusedPaneID = c.lenient(.focusedPaneID)
        workspaces = c.lossyArray(.workspaces)
        tabs = c.lossyArray(.tabs)
        panes = c.lossyArray(.panes)
        agents = c.lossyArray(.agents)
    }
}

/// The `ping` result.
public struct Pong: Sendable, Equatable, Decodable {
    public let version: String
    public let `protocol`: Int
}

public enum HerdrProtocol {
    /// The socket protocol Shepherd was built and tested against.
    public static let tested = 22
}

/// How the running herdr compares with the protocol Shepherd was tested against.
public enum Compatibility: Sendable, Equatable {
    case matched, older(Int), newer(Int)

    public init(protocol value: Int) {
        if value == HerdrProtocol.tested { self = .matched }
        else if value < HerdrProtocol.tested { self = .older(value) }
        else { self = .newer(value) }
    }
}
