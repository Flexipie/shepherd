import Darwin
import Foundation
import HerdrFake
import HerdrKit

// Records a sanitised fixture from the running herdr: one snapshot plus the events that arrive
// in the next few seconds. Usage: swift run RecordFixture <name> [seconds]
// Writes Sources/HerdrFake/Fixtures/<name>.json. Review it before committing.

let arguments = CommandLine.arguments.dropFirst()
guard let name = arguments.first, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
    FileHandle.standardError.write(Data("usage: RecordFixture <name> [seconds]\n".utf8))
    exit(2)
}
let seconds = arguments.dropFirst().first.flatMap(Int.init) ?? 0
let path = HerdrSocket.defaultPath()

func request(_ method: String, _ params: [String: Any] = [:]) throws -> (fd: Int32, reply: [String: Any]) {
    let fd = try UnixSocket.connect(path: path)
    UnixSocket.setTimeout(fd, .seconds(5))
    var line = try JSONSerialization.data(withJSONObject: ["id": "record-1", "method": method, "params": params])
    line.append(0x0A)
    try UnixSocket.writeAll(fd, line)
    let reply = try UnixSocket.readLineExact(fd, maxLength: LineBuffer.defaultMaxLineLength)
    guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any], object["result"] != nil else {
        throw HerdrError.unexpectedResponse(String(decoding: reply, as: UTF8.self))
    }
    return (fd, object)
}

do {
    let (snapshotFD, snapshotReply) = try request("session.snapshot")
    close(snapshotFD)
    guard let result = snapshotReply["result"] as? [String: Any], let snapshot = result["snapshot"] as? [String: Any] else {
        throw HerdrError.unexpectedResponse("no snapshot")
    }

    var events: [Any] = []
    if seconds > 0 {
        let panes = (snapshot["panes"] as? [[String: Any]] ?? []).compactMap { $0["pane_id"] as? String }
        let set = SubscriptionSet(paneIDs: Set(panes))
        let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(set.params))
        let (fd, _) = try request("events.subscribe", params as? [String: Any] ?? [:])
        let connection = LineConnection(fd: fd)
        print("recording events for \(seconds)s...")
        let collected = await withTaskGroup(of: [Data].self) { group in
            group.addTask {
                var lines: [Data] = []
                do { for try await line in connection.lines { lines.append(line) } } catch {}
                return lines
            }
            try? await Task.sleep(for: .seconds(seconds))
            connection.close()
            return await group.next() ?? []
        }
        events = collected.compactMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    var sanitiser = Sanitiser()
    let clean = sanitiser.sanitise(["snapshot": snapshot, "events": events]) as! [String: Any]
    let fixture = RecordedFixture(snapshot: try JSONSerialization.data(withJSONObject: clean["snapshot"]!),
                                  events: (clean["events"] as? [Any] ?? []).compactMap { try? JSONSerialization.data(withJSONObject: $0) })
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let output = root.appendingPathComponent("HerdrFake/Fixtures/\(name).json")
    try fixture.encoded().write(to: output)
    print("wrote \(output.path) (\(events.count) events)")
} catch {
    FileHandle.standardError.write(Data("record failed: \(error)\n".utf8))
    exit(1)
}
