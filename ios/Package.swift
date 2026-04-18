// swift-tools-version:5.9
import PackageDescription

// Standalone SwiftPM package for unit-testing the pure-logic parts of
// the QuietPlay tvOS app. The Logic target points at the same Swift
// files that the Xcode app compiles — no duplication.
//
// Run from ios/:
//     swift test
let package = Package(
    name: "QuietPlayLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "QuietPlayLogic",
            path: "QuietPlay/QuietPlay",
            sources: [
                "Models.swift",
                "PickerBuilder.swift",
            ]
        ),
        .testTarget(
            name: "QuietPlayLogicTests",
            dependencies: ["QuietPlayLogic"],
            path: "Tests/QuietPlayLogicTests"
        ),
    ]
)
