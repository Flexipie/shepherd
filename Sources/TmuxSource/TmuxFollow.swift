import TmuxKit

/// Where Shepherd's one control client on a server sits, so tmux behaves as it would without it.
/// tmux counts a control client as attached, and a plain `tmux attach` goes to the most recently used
/// session no client is on (any session when every one has a client). The client's own session hears
/// output directly; a subscription watches the rest (`TmuxActivity`).
///
/// - A session a terminal is on: attaching there changes nothing. The most recent one, which is
///   where an attach would bump it anyway.
/// - Otherwise the least recently used session no terminal is on, "parked": while another session
///   has no terminal either, an attach goes there, not to the parked one, so no pick changes. When
///   it is the last session without a terminal, the client moves to a terminal's session. A lone
///   session is parked on: any attach picks it anyway. Attaching makes the parked session the
///   most recent, so a parked client stays put rather than chasing the least recent one; after
///   Shepherd quits, that session looks recently used.
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
        let unviewed = sessions.filter { !viewed.contains($0.name) }
        let alone = sessions.count == 1
        func parkable(_ session: TmuxSession) -> Bool {
            !session.closesWhenUnattached && (alone || unviewed.contains { $0.id != session.id })
        }
        if let current, let session = sessions.first(where: { $0.id == current.session }) {
            if viewed.contains(session.name) { return Choice(session: session.id, parked: false) }
            // A terminal that leaves its session makes it the user's latest, so the client moves off.
            if current.parked, parkable(session) { return current }
        }
        if let session = sessions.last(where: { viewed.contains($0.name) }) {
            return Choice(session: session.id, parked: false)
        }
        return unviewed.first(where: parkable).map { Choice(session: $0.id, parked: true) }
    }
}

/// What a control client's subscription reports for every pane on its server: the pane, then its
/// cursor, history size and window activity, which change when the pane prints, and the command
/// in front, which changes when an agent starts. tmux checks it once a second, so a pane outside
/// the client's session is heard within about a second. The value covers every session, so it
/// carries over when the client moves.
enum TmuxActivity {
    static let subscription = "shepherd-panes"
    /// No commas: inside `#{S:}`, `#{W:}` and `#{P:}` a comma starts the format for the current
    /// item. The command comes last and may hold spaces; every entry starts with its pane id, so
    /// entries split on " %". tmux expands this every second for every pane, so it stays plain.
    static let format = "#{S:#{W:#{P:#{pane_id}=#{cursor_x}.#{cursor_y}.#{history_size}.#{window_activity}.#{pane_current_command} }}}"

    /// Each pane's signature, by pane id such as `%3`. A window in several sessions repeats; the same value.
    static func parse(_ value: String) -> [String: String] {
        var panes: [String: String] = [:]
        for (index, part) in value.dropLast(value.hasSuffix(" ") ? 1 : 0).components(separatedBy: " %").enumerated() {
            let entry = index == 0 ? Substring(part) : "%" + part
            guard entry.hasPrefix("%"), let equals = entry.firstIndex(of: "=") else { continue }
            panes[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return panes
    }

    /// Panes whose signature differs from `before`, new panes included.
    static func changed(from before: [String: String], to after: [String: String]) -> [String] {
        after.compactMap { pane, signature in before[pane] == signature ? nil : pane }
    }

    /// The command in front of the pane, the signature's last part. It may hold dots.
    static func command(_ signature: String?) -> Substring? {
        signature.flatMap { $0.split(separator: ".", maxSplits: 4, omittingEmptySubsequences: false).dropFirst(4).first }
    }
}
