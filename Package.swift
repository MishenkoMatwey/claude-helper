// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeAgentsMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeAgentsMonitor", targets: ["ClaudeAgentsMonitor"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAgentsMonitor",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/ClaudeAgentsMonitor",
            resources: [
                .process("Resources/BrandIcons"),
                .copy("Resources/AgentScripts")
            ]
        )
        // .testTarget — disabled because Command Line Tools without Xcode lacks XCTest/Testing C++ stdlib.
        // To enable: install Xcode, then uncomment and run `swift test`:
        // .testTarget(
        //     name: "ClaudeAgentsMonitorTests",
        //     dependencies: ["ClaudeAgentsMonitor"],
        //     path: "Tests/ClaudeAgentsMonitorTests"
        // )
    ]
)
