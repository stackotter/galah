// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Interpreter",
    products: [
        .library(
            name: "Interpreter",
            targets: ["Interpreter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "cli",
            dependencies: [
                "Interpreter",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "Interpreter"
        ),
        .testTarget(
            name: "InterpreterTests",
            dependencies: ["Interpreter"]
        ),
    ]
)
