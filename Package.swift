import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "CairnKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Cairn",
            dependencies: ["CairnKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CairnKitTests",
            dependencies: ["CairnKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
