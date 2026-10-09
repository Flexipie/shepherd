import Foundation
import HerdrFake

// Runs a fake herdr for trying Shepherd without real agents.
// Usage: swift run FakeHerdr [socket-path]
// Then: HERDR_SOCKET_PATH=<socket-path> build/Shepherd.app/Contents/MacOS/Shepherd
// Commands on stdin:
//   block|done|work|idle <pane>        change an agent's state
//   add <pane> [kind]                  add a working agent (its workspace is created if needed)
//   remove <pane>                      close a pane
//   label <workspace> <text>           add or rename a workspace
//   token <workspace|pane> key=value   set a token; key= removes it
//   lost, stop, start                  events_lost, herdr quitting, herdr returning
//   list, focused, quit

// Line-buffered, so output piped to a file shows up as it happens.
setvbuf(stdout, nil, _IOLBF, 0)

let path = CommandLine.arguments.dropFirst().first ?? "/tmp/shepherd-fake.sock"
let fake = FakeHerdrServer(herd: .basic, path: path)
try await fake.start()
print("fake herdr on \(path)")
print("commands: block|done|work|idle <pane>, add <pane> [kind], remove <pane>, label <workspace> <text>,")
print("          token <workspace|pane> key=value, lost, stop, start, list, focused, quit")

while let line = readLine() {
    let words = line.split(separator: " ").map(String.init)
    guard let command = words.first else { continue }
    let pane = words.count > 1 ? words[1] : ""
    switch command {
    case "block": await fake.setStatus(pane, "blocked")
    case "done": await fake.setStatus(pane, "done")
    case "work": await fake.setStatus(pane, "working")
    case "idle": await fake.setStatus(pane, "idle")
    case "add":
        let workspace = String(pane.prefix { $0 != ":" })
        if await !fake.herd.workspaces.contains(where: { $0.id == workspace }) {
            await fake.setWorkspace(workspace, label: workspace)
        }
        let kind = words.count > 2 ? words[2] : "claude"
        await fake.addPane(FakeHerd.Pane(id: pane, workspaceID: workspace, agent: kind, status: "working"))
    case "label":
        await fake.setWorkspace(pane, label: words.dropFirst(2).joined(separator: " "))
    case "token":
        let rest = words.dropFirst(2).joined(separator: " ")
        guard let equals = rest.firstIndex(of: "=") else {
            print("usage: token <workspace|pane> key=value")
            continue
        }
        await fake.setToken(pane, String(rest[..<equals]), String(rest[rest.index(after: equals)...]))
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
