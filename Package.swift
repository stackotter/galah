// swift-tools-version: 5.9

import CompilerPluginSupport
import Foundation
import PackageDescription

let noWasm = ProcessInfo.processInfo.environment["NO_WASM"] == "1"

let wasmTarget: Target = .executableTarget(
    name: "GalahWeb",
    dependencies: [
        "GalahInterpreter",
        "JavaScriptKit",
    ],
    linkerSettings: [
        .unsafeFlags(
            [
                "-Xlinker", "--export=main",
                "-Xclang-linker", "-mexec-model=reactor",
            ]
        )
    ]
)

let package = Package(
    name: "galah",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "GalahInterpreter",
            targets: ["GalahInterpreter"]
        )
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
        .package(url: "https://github.com/swiftwasm/carton", from: "1.0.0"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", exact: "0.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "galah",
            dependencies: [
                "GalahInterpreter",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
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
    ] + (noWasm ? [] : [wasmTarget])
)
