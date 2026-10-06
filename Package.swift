// swift-tools-version: 6.0
import PackageDescription
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let package = Package(
    name: "Clicky",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "ClickyApp", targets: ["ClickyApp"])],
    targets: [
        .target(name: "ClickyCore", swiftSettings: v5),
        .target(name: "ClickyGemini", dependencies: ["ClickyCore", "ClickyAudio", "ClickySafety"], swiftSettings: v5),
        .target(name: "ClickyAccessibility", dependencies: ["ClickyCore"], swiftSettings: v5),
        .target(name: "ClickyInput", dependencies: ["ClickyCore"], swiftSettings: v5),
        .target(name: "ClickySafety", dependencies: ["ClickyCore"], swiftSettings: v5),
        .target(name: "ClickyAudio", dependencies: ["ClickyCore"], swiftSettings: v5),
        .target(name: "ClickyVision", dependencies: ["ClickyCore"], swiftSettings: v5),
        .target(name: "ClickyOverlay", dependencies: ["ClickyCore"], swiftSettings: v5),
        .executableTarget(
            name: "ClickyApp",
            dependencies: ["ClickyCore", "ClickyGemini", "ClickyAccessibility", "ClickyInput",
                           "ClickySafety", "ClickyAudio", "ClickyVision", "ClickyOverlay"],
            swiftSettings: v5),
        .testTarget(name: "ClickyCoreTests", dependencies: ["ClickyCore"], swiftSettings: v5),
        .testTarget(name: "ClickyGeminiTests", dependencies: ["ClickyGemini", "ClickySafety"], swiftSettings: v5),
        .testTarget(name: "ClickyAccessibilityTests", dependencies: ["ClickyAccessibility"], swiftSettings: v5),
        .testTarget(name: "ClickyInputTests", dependencies: ["ClickyInput"], swiftSettings: v5),
        .testTarget(name: "ClickySafetyTests", dependencies: ["ClickySafety"], swiftSettings: v5),
        .testTarget(name: "ClickyAudioTests", dependencies: ["ClickyAudio"], swiftSettings: v5),
        .testTarget(name: "ClickyOverlayTests", dependencies: ["ClickyOverlay", "ClickyCore"], swiftSettings: v5),
        .testTarget(name: "ClickyAppTests",
                    dependencies: ["ClickyApp", "ClickyCore", "ClickyGemini", "ClickySafety"],
                    swiftSettings: v5),
    ]
)
