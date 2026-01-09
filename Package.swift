// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Hyperlink",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Hyperlink",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Hyperlink.entitlements"]
        ),
        .testTarget(
            name: "HyperlinkTests",
            dependencies: ["Hyperlink"]
        ),
    ]
)
