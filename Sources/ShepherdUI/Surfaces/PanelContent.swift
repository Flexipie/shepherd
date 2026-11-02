import ShepherdCore

/// Everything the notch bar and the palette's Status page show, computed by the app from the
/// modules and the store.
public struct PanelContent: Sendable, Equatable {
    public var sections: [PanelSection]
    /// The herd's state, then each source's own lines.
    public var statusLines: [String]
    /// Config problems, shown so a broken edit is never silent.
    public var problems: [String]

    public init(sections: [PanelSection], statusLines: [String] = [], problems: [String] = []) {
        self.sections = sections
        self.statusLines = statusLines
        self.problems = problems
    }
}
