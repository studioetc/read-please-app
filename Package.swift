// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReadPlease",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Vendored with its #Preview blocks removed so Command Line Tools builds work — see ThirdParty/KeyboardShortcuts/VENDORED.md.
        .package(path: "ThirdParty/KeyboardShortcuts")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ReadPlease",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "ReadPleaseTests",
            dependencies: ["ReadPlease"]
        ),
    ]
)
