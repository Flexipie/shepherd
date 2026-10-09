// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Shepherd",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Shepherd", targets: ["Shepherd"]),
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
        // Built-in features, one folder per module.
        .target(name: "ShepherdModules", dependencies: ["ShepherdCore"]),
        // SwiftUI views for the panel and the notch pill. Values in, no windows, no glass, so
        // every view can be snapshot tested.
        .target(name: "ShepherdUI", dependencies: ["ShepherdCore"]),
        // The app: menu bar item, panel, notch pill, settings.
        .executableTarget(name: "Shepherd", dependencies: ["ShepherdModules", "ShepherdCore", "ShepherdUI", "HerdrSource"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit", "HerdrFake"]),
        .testTarget(name: "HerdrSourceTests", dependencies: ["HerdrSource", "HerdrKit", "HerdrFake", "ShepherdCore"]),
        .testTarget(name: "ShepherdCoreTests", dependencies: ["ShepherdCore", "ShepherdModules"]),
        .testTarget(name: "ShepherdUITests", dependencies: ["ShepherdUI", "ShepherdCore"], exclude: ["__Snapshots__"]),
    ]
)
