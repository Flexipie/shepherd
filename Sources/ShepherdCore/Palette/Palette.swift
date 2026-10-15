/// What choosing something in the palette does.
public enum PaletteAction: Sendable, Hashable {
    case jump(AgentID)
    case focusProject(ProjectID)
    /// Jumps to the next agent that needs the user, like the "next" hotkey.
    case nextInQueue
}

/// A command a module offers in the palette. Modules contribute them, so the palette grows
/// without a central list.
public struct PaletteCommand: Sendable, Equatable, Identifiable {
    /// Stable and unique across modules, such as "queue.next".
    public let id: String
    public let title: String
    /// An SF Symbol name.
    public let symbol: String
    /// More words the command is found by.
    public let keywords: [String]
    public let action: PaletteAction

    public init(id: String, title: String, symbol: String, keywords: [String] = [], action: PaletteAction) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keywords = keywords
        self.action = action
    }
}

/// One thing the palette can find: an agent, a project or a command.
public struct PaletteItem: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case agent(PanelAgentRow)
        case project(HerdProject, agentCount: Int, tokens: [[StyledToken]])
        case command(PaletteCommand)
    }

    public let id: String
    public let kind: Kind
    /// The words it is found by, the title first. Highlights are shown on the title only.
    public let searchText: [String]
    /// nil when its source cannot do it; choosing it then does nothing.
    public let action: PaletteAction?

    public init(id: String, kind: Kind, searchText: [String], action: PaletteAction?) {
        self.id = id
        self.kind = kind
        self.searchText = searchText
        self.action = action
    }

    /// The name shown in bold, which highlights refer to.
    public var title: String { searchText.first ?? "" }

    /// An agent waiting on the user.
    public var needsYou: Bool {
        if case .agent(let row) = kind { row.agent.status.needsYou } else { false }
    }
}

/// An item that matched, with the matched characters of its title.
public struct PaletteResult: Sendable, Equatable, Identifiable {
    public let item: PaletteItem
    public let highlights: [Range<String.Index>]

    public init(item: PaletteItem, highlights: [Range<String.Index>] = []) {
        self.item = item
        self.highlights = highlights
    }

    public var id: String { item.id }
}
