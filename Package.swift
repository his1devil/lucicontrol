// swift-tools-version: 6.0
import PackageDescription

// LuciControlCore holds everything that does not need AppKit: the panel's model, the demo
// data taken from the design canvas, formatting rules, and later the control-channel
// client. It builds and tests with `swift test` alone.
let package = Package(
    name: "LuciControlCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LuciControlCore", targets: ["LuciControlCore"]),
    ],
    targets: [
        .target(name: "LuciControlCore", path: "Sources/Core"),
        // Fixtures: what lucirund's control channel sends (ContractTests reads them from the
        // source tree; lucirund's TestExportControlFixtures writes them).
        .testTarget(name: "LuciControlCoreTests", dependencies: ["LuciControlCore"], path: "Tests/Core", exclude: ["Fixtures"]),
    ]
)
