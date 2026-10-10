import Foundation
import HerdrKit

/// A fake herdr on a real Unix socket. It answers `ping`, `session.snapshot`, `agent.focus`,
/// `workspace.focus` and `events.subscribe` the way herdr 0.9.3 does: one request per connection, subscriptions
/// validated against the current panes, both event name spellings, `events_lost` as an error
/// carrying the subscribe id. Tests drive it and observe what the client did; demo mode will
/// reuse it.
public actor FakeHerdrServer {
    public nonisolated let path: String
    public private(set) var herd: FakeHerd

    /// Delay before answering a snapshot.
    public var snapshotDelay: Duration = .zero
    /// When true, snapshot requests are never answered.
    public var stallSnapshots = false
    /// A recorded snapshot served instead of `herd`, for fixture and demo use.
    public private(set) var recordedSnapshot: Data?

    public private(set) var requests: [String] = []
    public private(set) var snapshotCount = 0
    public private(set) var maxConcurrentSnapshots = 0
    public private(set) var focusedTargets: [String] = []
    public private(set) var focusedWorkspaces: [String] = []
    /// The fewest live subscribers seen since the first one started; nil before that.
    public private(set) var subscriberLowWater: Int?
    public var subscriberCount: Int { subscribers.count }
    public var subscribedPaneSets: [Set<String>] { subscribers.values.map(\.paneIDs) }

    struct Subscriber {
        let requestID: String
        let paneIDs: Set<String>
        let connection: LineConnection
    }

    private var listener: UnixListener?
    private var connections: [Int: LineConnection] = [:]
    /// Stalled requests, kept open (unanswered) until the client gives up or the fake stops.
    private var held: [LineConnection] = []
    private var subscribers: [Int: Subscriber] = [:]
    private var nextConnectionID = 0
    private var inFlightSnapshots = 0
    var waiters: [Int: Waiter] = [:]
    var nextWaiterID = 0

    /// Uses a short random path under /tmp, so tests can run in parallel within `sun_path` limits.
    public init(herd: FakeHerd = .basic, path: String? = nil) {
        self.herd = herd
        self.path = path ?? "/tmp/shf-\(UUID().uuidString.prefix(8).lowercased()).sock"
    }

    // MARK: Lifecycle

    public func start() throws {
        guard listener == nil else { return }
        listener = try UnixListener(path: path) { [weak self] fd in
            guard let self else { return }
            Task { await self.accept(fd) }
        }
    }

    /// Stops listening and closes every connection, like herdr quitting.
    public func stop() {
        listener?.close()
        listener = nil
        for connection in connections.values { connection.close() }
        for connection in held { connection.close() }
        held.removeAll()
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func setSnapshotDelay(_ delay: Duration) { snapshotDelay = delay }
    public func setStallSnapshots(_ stall: Bool) { stallSnapshots = stall }

    /// Serves a recorded snapshot instead of the built herd.
    public func serve(_ fixture: RecordedFixture) {
        recordedSnapshot = fixture.snapshot
    }

    private var knownPaneIDs: Set<String> {
        guard let recordedSnapshot,
              let object = try? JSONSerialization.jsonObject(with: recordedSnapshot) as? [String: Any],
              let panes = object["panes"] as? [[String: Any]] else { return Set(herd.panes.map(\.id)) }
        return Set(panes.compactMap { $0["pane_id"] as? String })
    }

    // MARK: Changing the herd

    /// Changes the herd without emitting events.
    public func update(_ change: @Sendable (inout FakeHerd) -> Void) {
        change(&herd)
    }

    /// Changes a pane's status and pushes `pane.agent_status_changed` to subscribers of that pane.
    public func setStatus(_ paneID: String, _ status: String) {
        herd.setStatus(paneID, status)
        pushStatus(paneID)
    }

    /// herdr notices a status change on a subscribed pane (including `done` clearing on focus,
    /// which it finds by checking each subscribed pane) and pushes it.
    private func pushStatus(_ paneID: String) {
        guard let pane = herd.panes.first(where: { $0.id == paneID }) else { return }
        let event: [String: Any] = ["event": "pane.agent_status_changed",
                                    "data": ["pane_id": paneID, "workspace_id": pane.workspaceID, "agent_status": pane.status]]
        for subscriber in subscribers.values where subscriber.paneIDs.contains(paneID) {
            try? subscriber.connection.write(Self.line(event))
        }
    }

    /// Pushes a lifecycle event (underscore spelling, `data.type` set) to every subscriber.
    public func emit(_ kind: String, data: [String: String] = [:]) {
        var payload: [String: Any] = data
        payload["type"] = kind
        let event: [String: Any] = ["event": kind, "data": payload]
        for subscriber in subscribers.values { try? subscriber.connection.write(Self.line(event)) }
    }

    /// A shell pane starts running an agent, as herdr's detection reports it.
    public func detectAgent(_ paneID: String, kind: String, status: String = "working") {
        guard let index = herd.panes.firstIndex(where: { $0.id == paneID }) else { return }
        herd.panes[index].agent = kind
        herd.panes[index].status = "unknown"
        herd.setStatus(paneID, status)
        emit("pane_agent_detected", data: ["pane_id": paneID, "workspace_id": herd.panes[index].workspaceID, "agent": kind])
    }

    public func addPane(_ pane: FakeHerd.Pane) {
        herd.panes.append(pane)
        emit("pane_created", data: ["pane_id": pane.id, "workspace_id": pane.workspaceID])
    }

    /// Adds a workspace, or renames it if it exists.
    public func setWorkspace(_ id: String, label: String) {
        if let index = herd.workspaces.firstIndex(where: { $0.id == id }) {
            herd.workspaces[index].label = label
            emit("workspace_renamed", data: ["workspace_id": id])
        } else {
            herd.workspaces.append(FakeHerd.Workspace(id: id, label: label))
            emit("workspace_created", data: ["workspace_id": id])
        }
    }

    /// Sets a token on a workspace or a pane (an id with a `:` is a pane); an empty value removes
    /// it, as `report_metadata` does.
    public func setToken(_ target: String, _ key: String, _ value: String) {
        if let index = herd.panes.firstIndex(where: { $0.id == target }) {
            herd.panes[index].tokens[key] = value.isEmpty ? nil : value
            emit("pane_updated", data: ["pane_id": target])
        } else if let index = herd.workspaces.firstIndex(where: { $0.id == target }) {
            herd.workspaces[index].tokens[key] = value.isEmpty ? nil : value
            emit("workspace_metadata_updated", data: ["workspace_id": target])
        }
    }

    public func removePane(_ paneID: String) {
        herd.panes.removeAll { $0.id == paneID }
        emit("pane_closed", data: ["pane_id": paneID])
    }

    /// Tells every subscriber it fell behind, then closes it, as herdr does.
    public func sendEventsLost() {
        for subscriber in subscribers.values {
            let error: [String: Any] = ["id": subscriber.requestID, "error": ["code": "events_lost", "message": "subscriber fell behind"]]
            try? subscriber.connection.write(Self.line(error))
            subscriber.connection.close()
        }
    }

    public func dropSubscribers() {
        for subscriber in subscribers.values { subscriber.connection.close() }
    }

    public func requestCount(_ method: String) -> Int {
        requests.filter { $0 == method }.count
    }

    // MARK: Serving

    private func accept(_ fd: Int32) async {
        let id = nextConnectionID
        nextConnectionID += 1
        let connection = LineConnection(fd: fd)
        connections[id] = connection
        await serve(id, connection)
        connections[id] = nil
        if subscribers.removeValue(forKey: id) != nil { subscribersChanged() }
    }

    private func serve(_ id: Int, _ connection: LineConnection) async {
        var lines = connection.lines.makeAsyncIterator()
        guard let line = try? await lines.next(),
              let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let requestID = request["id"] as? String,
              let method = request["method"] as? String
        else {
            connection.close()
            return
        }
        let params = request["params"] as? [String: Any] ?? [:]
        requests.append(method)
        resumeWaiters()

        switch method {
        case "ping":
            reply(connection, requestID, ["type": "pong", "version": herd.version, "protocol": herd.protocolVersion])
        case "session.snapshot":
            await serveSnapshot(connection, requestID)
        case "agent.focus":
            let target = params["target"] as? String ?? ""
            focusedTargets.append(target)
            guard let workspace = herd.panes.first(where: { $0.id == target })?.workspaceID else {
                replyError(connection, requestID, code: "pane_not_found", message: "pane not found")
                return
            }
            let seen = herd.focus(workspace: workspace, pane: target)
            reply(connection, requestID, ["type": "ok"])
            emit("workspace_focused", data: ["workspace_id": workspace])
            emit("pane_focused", data: ["pane_id": target, "workspace_id": workspace])
            seen.forEach(pushStatus)
        case "workspace.focus":
            let workspace = params["workspace_id"] as? String ?? ""
            guard herd.workspaces.contains(where: { $0.id == workspace }) else {
                replyError(connection, requestID, code: "workspace_not_found", message: "workspace not found")
                return
            }
            focusedWorkspaces.append(workspace)
            let seen = herd.focus(workspace: workspace)
            reply(connection, requestID, ["type": "ok"])
            emit("workspace_focused", data: ["workspace_id": workspace])
            seen.forEach(pushStatus)
        case "events.subscribe":
            let entries = params["subscriptions"] as? [[String: Any]] ?? []
            let paneIDs = Set(entries.compactMap { $0["pane_id"] as? String })
            guard paneIDs.isSubset(of: knownPaneIDs) else {
                replyError(connection, requestID, code: "pane_not_found", message: "pane not found")
                return
            }
            send(connection, ["id": requestID, "result": ["type": "subscription_started"]])
            subscribers[id] = Subscriber(requestID: requestID, paneIDs: paneIDs, connection: connection)
            subscribersChanged()
            while (try? await lines.next()) != nil {}
            return
        default:
            replyError(connection, requestID, code: "invalid_request", message: "unknown method \(method)")
        }
    }

    private func serveSnapshot(_ connection: LineConnection, _ requestID: String) async {
        snapshotCount += 1
        inFlightSnapshots += 1
        maxConcurrentSnapshots = max(maxConcurrentSnapshots, inFlightSnapshots)
        resumeWaiters()
        defer { inFlightSnapshots -= 1 }
        // Stalled: leave the connection open and unanswered; the client's timeout closes it.
        if stallSnapshots {
            held.append(connection)
            return
        }
        if snapshotDelay > .zero { try? await Task.sleep(for: snapshotDelay) }
        let recorded = recordedSnapshot.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        reply(connection, requestID, ["type": "session_snapshot", "snapshot": recorded ?? herd.snapshotJSON()])
    }

    private func subscribersChanged() {
        if subscriberLowWater != nil || !subscribers.isEmpty {
            subscriberLowWater = min(subscriberLowWater ?? subscribers.count, subscribers.count)
        }
        resumeWaiters()
    }

    private func reply(_ connection: LineConnection, _ id: String, _ result: [String: Any]) {
        send(connection, ["id": id, "result": result])
        connection.close()
    }

    private func replyError(_ connection: LineConnection, _ id: String, code: String, message: String) {
        send(connection, ["id": id, "error": ["code": code, "message": message]])
        connection.close()
    }

    private func send(_ connection: LineConnection, _ object: [String: Any]) {
        try? connection.write(Self.line(object))
    }

    static func line(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}
