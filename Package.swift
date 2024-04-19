// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "galah",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "GalahInterpreter",
            targets: ["GalahInterpreter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(
            url: "https://github.com/apple/swift-syntax.git",
            from: "509.0.0"
        ),
        .package(
            url: "https://github.com/stackotter/swift-macro-toolkit",
            from: "0.3.1"
        ),
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
            name: "GalahInterpreter",
            dependencies: [
                "UtilityMacros"
            ]
        ),

        .macro(
            name: "UtilityMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "MacroToolkit", package: "swift-macro-toolkit"),
            ]
        ),
        .target(name: "UtilityMacros", dependencies: ["UtilityMacrosPlugin"]),

        .testTarget(
            name: "GalahInterpreterTests",
            dependencies: ["GalahInterpreter"]
        ),
    ]
)
