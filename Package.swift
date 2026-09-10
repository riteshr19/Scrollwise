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
        // The event tap, its thread, and the engine that owns it. A library rather
        // than part of the app so ScrollwiseTapCheck can drive the real tap.
        .target(
            name: "ScrollwiseEngine",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ScrollwiseApp",
            dependencies: ["ScrollwiseCore", "ScrollwiseEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Runs the same assertions as the test suite without swift-testing, so
        // the core can be verified from a Command Line Tools toolchain or CI.
        .executableTarget(
            name: "ScrollwiseVerify",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Live checks against the real event tap: lifecycle and duplicate-tap
        // defence, end-to-end direction, the gesture latch, recovery from a
        // timeout, and callback latency. Needs Accessibility, so it is run by
        // hand rather than in CI. Never part of the shipped app.
        .executableTarget(
            name: "ScrollwiseTapCheck",
            dependencies: ["ScrollwiseCore", "ScrollwiseEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScrollwiseCoreTests",
            dependencies: ["ScrollwiseCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
