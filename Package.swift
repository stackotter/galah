// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "galah",
    products: [
        .library(
            name: "GalahInterpreter",
            targets: ["GalahInterpreter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "galah",
            dependencies: [
                "GalahInterpreter",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "GalahInterpreter"
        ),
        .testTarget(
            name: "GalahInterpreterTests",
            dependencies: ["GalahInterpreter"]
        ),
    ]
)
