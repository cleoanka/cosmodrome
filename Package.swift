// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cosmodrome",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "CosmodromeCore",
            path: "Sources/CosmodromeCore"
        ),
        .executableTarget(
            name: "Cosmodrome",
            dependencies: ["CosmodromeCore"],
            path: "Sources/Cosmodrome"
        ),
        .testTarget(
            name: "CosmodromeCoreTests",
            dependencies: ["CosmodromeCore"],
            path: "Tests/CosmodromeCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
