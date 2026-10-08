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
        .target(name: "HerdrFake", dependencies: ["HerdrKit"]),
        // Module protocol, registry, config, token rules and action templates.
        .target(name: "ShepherdCore", dependencies: ["HerdrKit"]),
        // Built-in features, one folder per module.
        .target(name: "ShepherdModules", dependencies: ["ShepherdCore", "HerdrKit"]),
        // The app: menu bar item, panel, notch pill, settings.
        .executableTarget(name: "Shepherd", dependencies: ["ShepherdModules", "ShepherdCore", "HerdrKit"]),
        .testTarget(name: "HerdrKitTests", dependencies: ["HerdrKit", "HerdrFake"]),
    ]
)
