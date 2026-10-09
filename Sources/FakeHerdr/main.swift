import Foundation
import HerdrFake

// Runs a fake herdr for trying Shepherd without real agents.
// Usage: swift run FakeHerdr [socket-path]
// Then: HERDR_SOCKET_PATH=<socket-path> build/Shepherd.app/Contents/MacOS/Shepherd
// Commands on stdin: block|done|work|idle <pane>, add <pane>, remove <pane>, lost, stop, start, list, quit

// Line-buffered, so output piped to a file shows up as it happens.
setvbuf(stdout, nil, _IOLBF, 0)

let path = CommandLine.arguments.dropFirst().first ?? "/tmp/shepherd-fake.sock"
let fake = FakeHerdrServer(herd: .basic, path: path)
try await fake.start()
print("fake herdr on \(path)")
print("commands: block|done|work|idle <pane>, add <pane>, remove <pane>, lost, stop, start, list, quit")

while let line = readLine() {
    let words = line.split(separator: " ").map(String.init)
    guard let command = words.first else { continue }
    let pane = words.count > 1 ? words[1] : ""
    switch command {
    case "block": await fake.setStatus(pane, "blocked")
    case "done": await fake.setStatus(pane, "done")
    case "work": await fake.setStatus(pane, "working")
    case "idle": await fake.setStatus(pane, "idle")
    case "add": await fake.addPane(FakeHerd.Pane(id: pane, workspaceID: String(pane.prefix { $0 != ":" }), status: "working"))
    case "remove": await fake.removePane(pane)
    case "lost": await fake.sendEventsLost()
    case "stop": await fake.stop()
    case "start": try await fake.start()
    case "focused":
        print("agents:", await fake.focusedTargets, "workspaces:", await fake.focusedWorkspaces)
    case "list":
        for pane in await fake.herd.panes { print(pane.id, pane.agent ?? "shell", pane.status) }
    case "quit":
        await fake.stop()
        exit(0)
    default: print("unknown command: \(command)")
    }
}
