// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenInk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenInk", targets: ["ScreenInk"]),
    ],
    targets: [
        // Pure model and geometry: no AppKit, fully unit-tested.
        .target(name: "ScreenInkCore"),
        // The menu-bar app: overlay windows, input, rendering.
        .executableTarget(
            name: "ScreenInk",
            dependencies: ["ScreenInkCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ScreenCaptureKit")]
        ),
        .testTarget(name: "ScreenInkCoreTests", dependencies: ["ScreenInkCore"]),
    ]
)
