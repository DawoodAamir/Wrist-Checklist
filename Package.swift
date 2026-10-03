// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ChecklistCore", platforms: [.macOS(.v15)], products: [.library(name: "ChecklistCore", targets: ["ChecklistCore"])], targets: [.target(name: "ChecklistCore", path: "Sources/Core"), .testTarget(name: "ChecklistTests", dependencies: ["ChecklistCore"], path: "Tests/Core")])
