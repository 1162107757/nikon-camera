// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HueviaCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "HueviaCore", targets: ["HueviaCore"])],
    targets: [
        .target(name: "HueviaCore", path: "Core"),
        .testTarget(name: "HueviaCoreTests", dependencies: ["HueviaCore"], path: "Tests")
    ],
    swiftLanguageVersions: [.v5]
)
