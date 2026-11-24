// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Sampler",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master"),
        .package(url: "https://github.com/NucleantUI/NucleantAudio.git", .upToNextMinor(from: "0.0.0")),
    ],
    targets: [
        .executableTarget(
            name: "Sampler",
            dependencies: [
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "NucleantAudio", package: "NucleantAudio"),
            ]
        ),
    ]
)
