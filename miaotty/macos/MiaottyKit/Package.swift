// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiaottyKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MiaottyKit", targets: ["MiaottyKit"]),
        .executable(name: "miaotty-host", targets: ["miaotty-host"]),
    ],
    targets: [
        .target(name: "MiaottyKit"),
        .executableTarget(name: "miaotty-host", dependencies: ["MiaottyKit"]),
        .testTarget(name: "MiaottyKitTests", dependencies: ["MiaottyKit"]),
    ]
)
