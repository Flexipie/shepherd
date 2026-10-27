import TmuxKit

/// Where Shepherd's one control client on a server sits, so tmux behaves as it would without it.
/// tmux counts a control client as attached, and a plain `tmux attach` goes to the most recently used
/// session no client is on (any session when every one has a client). The client's own session hears
/// output directly; a subscription watches the rest (`TmuxActivity`).
///
/// - A session a terminal is on: attaching there changes nothing. The most recent one, which is
///   where an attach would bump it anyway.
/// - Otherwise the least recently used session, "parked": it is the one an attach would pick last,
///   so taking it out of the running changes no pick, unless it is the only session, which any
///   attach picks anyway. Attaching makes it the most recent, so a parked client stays put rather
///   than chasing the least recent one.
/// - Never a session tmux closes once unattached (`destroy-unattached`) that no terminal is on:
///   the client would keep it open.
enum TmuxFollow {
    struct Choice: Equatable {
        /// Such as `$1`.
        let session: String
        let parked: Bool
    }

    /// `sessions` least recently used first (`TmuxClient.sessions`); `terminals` are the server's
    /// clients other than Shepherd's. Nil when there is no session to sit on.
    static func choose(sessions: [TmuxSession], terminals: [TmuxAttachedClient], current: Choice?) -> Choice? {
        let viewed = Set(terminals.map(\.session))
        if let current, let session = sessions.first(where: { $0.id == current.session }) {
            if viewed.contains(session.name) { return Choice(session: session.id, parked: false) }
            // A terminal that leaves its session makes it the user's latest, so the client moves off.
            if current.parked, !session.closesWhenUnattached { return current }
        }
        if let session = sessions.last(where: { viewed.contains($0.name) }) {
            return Choice(session: session.id, parked: false)
        }
        return sessions.first { !$0.closesWhenUnattached }.map { Choice(session: $0.id, parked: true) }
    }
}

/// What a control client's subscription reports for every pane on its server: the pane, then its
/// cursor, history size and window activity, which change when the pane prints. tmux checks it once
/// a second, so a pane outside the client's session is heard within about a second.
enum TmuxActivity {
    static let subscription = "shepherd-panes"
    /// No commas: inside `#{S:}`, `#{W:}` and `#{P:}` a comma starts the format for the current item.
    static let format = "#{S:#{W:#{P:#{pane_id}=#{cursor_x}.#{cursor_y}.#{history_size}.#{window_activity} }}}"

    /// Each pane's signature, by pane id such as `%3`. A window in several sessions repeats; the same value.
    static func parse(_ value: String) -> [String: String] {
        var panes: [String: String] = [:]
        for word in value.split(separator: " ") {
            guard let equals = word.firstIndex(of: "=") else { continue }
            panes[String(word[..<equals])] = String(word[word.index(after: equals)...])
        }
        return panes
    }

    /// Panes whose signature differs from `before`, new panes included.
    static func changed(from before: [String: String], to after: [String: String]) -> [String] {
        after.compactMap { pane, signature in before[pane] == signature ? nil : pane }
    }
}
