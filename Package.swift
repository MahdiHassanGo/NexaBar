// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NexaBar",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "NexaBar", targets: ["NexaBar"])
    ],
    targets: [
        .executableTarget(
            name: "NexaBar",
            path: "Sources/NexaBar",
            resources: [
                .process("AppIcon.png")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Combine")
            ]
        )
    ]
)
