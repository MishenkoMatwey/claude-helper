// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeAgentsMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeAgentsMonitor", targets: ["ClaudeAgentsMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeAgentsMonitor",
            path: "Sources/ClaudeAgentsMonitor"
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
