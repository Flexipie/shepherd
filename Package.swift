// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shepherd",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Shepherd", targets: ["Shepherd"]),
        // Provisional name: `shepherd` collides with the app's binary on a case-insensitive disk.
        .executable(name: "shepherd-report", targets: ["ShepherdReport"]),
        .library(name: "HerdrKit", targets: ["HerdrKit"]),
        .library(name: "HerdrFake", targets: ["HerdrFake"]),
    ],
    targets: [
        // herdr socket client, data models and the live session engine. No UI, no Shepherd.
        .target(name: "HerdrKit"),
        // A fake herdr on a real Unix socket, for tests and demo mode. No UI.
        .target(name: "HerdrFake", dependencies: ["HerdrKit"], resources: [.copy("Fixtures")]),
        // Dev tool: records a sanitised fixture from the running herdr (`make fixture`).
        .executableTarget(name: "RecordFixture", dependencies: ["HerdrKit", "HerdrFake"]),
        // Dev tool: a fake herdr driven from stdin, for trying Shepherd without real agents.
        .executableTarget(name: "FakeHerdr", dependencies: ["HerdrFake"]),
        // The herd model, sources and module protocols, shared store. No source types.
        .target(name: "ShepherdCore"),
        // herdr as a source: adapts HerdrKit to the herd model. The only target that sees both.
        .target(name: "HerdrSource", dependencies: ["HerdrKit", "ShepherdCore"]),
        // OpenUsage's local API as a usage reader: loopback only, read-only, no credentials.
        .target(name: "OpenUsageSource", dependencies: ["ShepherdCore"]),
        // The Mac's CPU and memory from Mach host calls, as a system sampler. No files, no I/O.
        .target(name: "SystemSource", dependencies: ["ShepherdCore"]),
        // Plugin commands as processes, for the plugin host in ShepherdCore.
        .target(name: "ShellPlugins", dependencies: ["ShepherdCore"]),
        // Claude Code's session files as a context reader: read-only, the file's tail only.
        .target(name: "ClaudeSessionSource", dependencies: ["ShepherdCore"]),
        // The spool format and `shepherd report`'s logic: files an agent writes to say its status. No UI.
        .target(name: "ReportKit"),
        // The `shepherd report` command: a 3-line main over ReportKit.
        .executableTarget(name: "ShepherdReport", dependencies: ["ReportKit"]),
        // Agent reports as a source: watches the spool and maps reports to the herd model.
        .target(name: "ReportSource", dependencies: ["ReportKit", "ShepherdCore"]),
        // tmux's command line, control mode and the process table. No UI, no Shepherd.
        .target(name: "TmuxKit"),
        // tmux as a source: panes running a known agent, read from their screens and labelled inferred.
        .target(name: "TmuxSource", dependencies: ["TmuxKit", "ShepherdCore"]),
        // A private tmux server on its own socket, for the tmux tests only.
        .target(name: "TmuxTestSupport", dependencies: ["TmuxKit"], path: "Tests/TmuxTestSupport"),
        // Demo mode's made-up herd: a fake herdr, reports and screen-read agents, all temporary.
        .target(name: "DemoHerd", dependencies: ["HerdrFake", "HerdrSource", "ReportKit", "ReportSource", "TmuxSource", "ShepherdCore"]),
        // Built-in features, one folder per module.
        .target(name: "ShepherdModules", dependencies: ["ShepherdCore"]),
        // SwiftUI views for the panel and the notch pill. Values in, no windows, no glass, so
        // every view can be snapshot tested.
        .target(name: "ShepherdUI", dependencies: ["ShepherdCore"]),
        // The app: menu bar item, panel, notch pill, settings.
        .executableTarget(name: "Shepherd", dependencies: ["ShepherdModules", "ShepherdCore", "ShepherdUI", "HerdrSource", "OpenUsageSource", "SystemSource", "ClaudeSessionSource", "ShellPlugins", "ReportSource", "TmuxSource", "DemoHerd"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit", "HerdrFake"]),
        .testTarget(name: "HerdrSourceTests", dependencies: ["HerdrSource", "HerdrKit", "HerdrFake", "ShepherdCore"]),
        .testTarget(name: "OpenUsageSourceTests", dependencies: ["OpenUsageSource", "ShepherdCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ClaudeSessionSourceTests", dependencies: ["ClaudeSessionSource", "ShepherdCore", "HerdrSource", "HerdrKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SystemSourceTests", dependencies: ["SystemSource", "ShepherdCore"]),
        .testTarget(name: "ShellPluginsTests", dependencies: ["ShellPlugins", "ShepherdCore"]),
        .testTarget(name: "ReportKitTests", dependencies: ["ReportKit"]),
        .testTarget(name: "ReportSourceTests", dependencies: ["ReportSource", "ReportKit", "ShepherdCore"]),
        .testTarget(name: "TmuxKitTests", dependencies: ["TmuxKit", "TmuxTestSupport"]),
        .testTarget(name: "TmuxSourceTests", dependencies: ["TmuxSource", "TmuxKit", "TmuxTestSupport", "ReportKit", "ReportSource", "ShepherdCore"]),
        .testTarget(name: "ShepherdCoreTests", dependencies: ["ShepherdCore", "ShepherdModules"]),
        .testTarget(name: "ShepherdUITests", dependencies: ["ShepherdUI", "ShepherdCore"], exclude: ["__Snapshots__"]),
    ]
)
