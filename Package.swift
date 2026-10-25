// swift-tools-version: 5.10
import PackageDescription

// AgentTouchbarCore and atb depend only on Foundation, so they build and test on Linux.
// The AgentTouchbar menu bar app depends on AppKit and is added on macOS only.
var targets: [Target] = [
    .target(
        name: "AgentTouchbarCore",
        dependencies: [.product(name: "Yams", package: "Yams")]
    ),
    .executableTarget(
        name: "atb",
        dependencies: ["AgentTouchbarCore"]
    ),
    .testTarget(
        name: "AgentTouchbarCoreTests",
        dependencies: ["AgentTouchbarCore"]
    ),
]

var products: [Product] = [
    .executable(name: "atb", targets: ["atb"])
]

#if os(macOS)
    targets.append(
        .executableTarget(
            name: "AgentTouchbar",
            dependencies: ["AgentTouchbarCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("EventKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
            ]
        )
    )
    products.append(.executable(name: "AgentTouchbar", targets: ["AgentTouchbar"]))
#endif

let package = Package(
    name: "agentTouchbar",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: targets
)
