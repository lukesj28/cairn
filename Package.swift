// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CairnKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Cairn",
            dependencies: ["CairnKit", .product(name: "Sparkle", package: "Sparkle")],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "CairnKitTests",
            dependencies: ["CairnKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
