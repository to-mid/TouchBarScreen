// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TouchBarScreen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TouchBarScreen", targets: ["TouchBarScreen"])
    ],
    targets: [
        .target(
            name: "TouchBarPrivateBridge",
            path: "Sources/TouchBarPrivateBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TouchBarScreen",
            dependencies: ["TouchBarPrivateBridge"],
            path: "Sources/TouchBarScreen"
        ),
        .testTarget(
            name: "TouchBarScreenTests",
            dependencies: ["TouchBarScreen"],
            path: "Tests/TouchBarScreenTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
