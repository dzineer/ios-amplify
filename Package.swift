// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicAmplifier",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "MicAmplifier", targets: ["MicAmplifier"])
    ],
    targets: [
        .target(name: "MicAmplifier", path: "Sources"),
        .testTarget(name: "MicAmplifierTests", dependencies: ["MicAmplifier"], path: "Tests")
    ]
)
