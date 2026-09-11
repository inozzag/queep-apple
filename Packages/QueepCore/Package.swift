// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QueepCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "QueepCore", targets: ["QueepCore"])],
    targets: [
        .target(name: "QueepCore"),
        .testTarget(name: "QueepCoreTests", dependencies: ["QueepCore"])
    ]
)
