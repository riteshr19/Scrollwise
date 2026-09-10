// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Scrollwise",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic. No AppKit, no CoreGraphics event APIs — so it is fully unit-testable
        // without generating physical input. See ScrollTransformer / DeviceClassifier.
        .target(
            name: "ScrollwiseCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ScrollwiseApp",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Runs the same assertions as the test suite without swift-testing, so
        // the core can be verified from a Command Line Tools toolchain or CI.
        .executableTarget(
            name: "ScrollwiseVerify",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScrollwiseCoreTests",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
