// swift-tools-version: 6.0
// The line above isn't a comment to Swift Package Manager: it says which
// version of the package format this file uses. Keep it first.

// NowboardKit: everything about task files, with no UI and no platform code.
// The iOS and macOS app targets both use it. `swift test` in this folder runs
// its tests, including every case in ../../fixtures/task-format/.

import PackageDescription

let package = Package(
    name: "NowboardKit",
    // The oldest systems the app supports.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NowboardKit", targets: ["NowboardKit"])
    ],
    dependencies: [
        // Reads the YAML frontmatter (docs/adr/0007-yams-for-yaml.md).
        // The exact version is pinned in Package.resolved.
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0")
    ],
    targets: [
        .target(name: "NowboardKit", dependencies: ["Yams"]),
        .testTarget(name: "NowboardKitTests", dependencies: ["NowboardKit"]),
    ]
)
