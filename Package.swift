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
        // herdr socket client, data models and the live session store. No UI.
        .target(name: "HerdrKit"),
        // A fake herdr on a real Unix socket, for tests and demo mode. No UI.
        .target(name: "HerdrFake", dependencies: ["HerdrKit"], resources: [.copy("Fixtures")]),
        // Dev tool: records a sanitised fixture from the running herdr (`make fixture`).
        .executableTarget(name: "RecordFixture", dependencies: ["HerdrKit", "HerdrFake"]),
        // Dev tool: a fake herdr driven from stdin, for trying Shepherd without real agents.
        .executableTarget(name: "FakeHerdr", dependencies: ["HerdrFake"]),
        // Module protocol, registry, config, token rules and action templates.
        .target(name: "ShepherdCore", dependencies: ["HerdrKit"]),
        // Built-in features, one folder per module.
        .target(name: "ShepherdModules", dependencies: ["ShepherdCore", "HerdrKit"]),
        // The app: menu bar item, panel, notch pill, settings.
        .executableTarget(name: "Shepherd", dependencies: ["ShepherdModules", "ShepherdCore", "HerdrKit"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit", "HerdrFake"]),
        .testTarget(name: "ShepherdCoreTests", dependencies: ["ShepherdCore", "ShepherdModules", "HerdrKit"]),
    ]
)
