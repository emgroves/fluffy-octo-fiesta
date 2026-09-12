// swift-tools-version: 6.0
import PackageDescription

// SwingCore deliberately depends on nothing but Foundation.
//
// Every algorithm that decides *what happened in a swing* lives here, expressed
// over plain numbers rather than CMSampleBuffer / VNHumanBodyPoseObservation.
// That keeps the interesting logic buildable and testable on any Swift toolchain
// — including CI and Linux — instead of only on a Mac with the iOS 27.1 SDK.
// Platform adapters that speak AVFoundation and Vision live in the app target.
let package = Package(
    name: "SwingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwingCore", targets: ["SwingCore"])
    ],
    targets: [
        .target(name: "SwingCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "SwingCoreTests",
            dependencies: ["SwingCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
