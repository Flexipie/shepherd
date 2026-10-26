import Observation

/// One place agents can come from, as the first-run guide explains it: what Shepherd found, what it
/// gives, and what to do to get it. Written by the app, which knows the sources; modules only show it.
public struct SourceIntro: Sendable, Equatable, Identifiable {
    /// What the guide says in one state: a word or two beside the name, then a sentence.
    public struct Text: Sendable, Equatable {
        public let detail: String
        public let line: String

        public init(_ detail: String, _ line: String) {
            self.detail = detail
            self.line = line
        }
    }

    public let id: String
    public let name: String
    /// The running source this is about. It is on while that source is live; without one, `found` says.
    public let source: SourceID?
    public let found: Bool
    public let on: Text
    public let off: Text

    public init(id: String, name: String, source: SourceID? = nil, found: Bool = false, on: Text, off: Text) {
        self.id = id
        self.name = name
        self.source = source
        self.found = found
        self.on = on
        self.off = off
    }
}

/// What the app found on this Mac at launch, in the order to explain it.
@MainActor
@Observable
public final class SourceGuide {
    public private(set) var intros: [SourceIntro] = []

    public init() {}

    public func set(_ intros: [SourceIntro]) {
        guard intros != self.intros else { return }
        self.intros = intros
    }

    /// Whether the intro is on: its source is live, or, without a source, it was found.
    public func isOn(_ intro: SourceIntro, in store: HerdStore) -> Bool {
        intro.source.map { store.sourceStates[$0]?.isLive == true } ?? intro.found
    }
}
