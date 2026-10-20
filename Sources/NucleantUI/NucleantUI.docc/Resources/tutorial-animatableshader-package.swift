// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AnimatableShader",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master"),
        .package(url: "https://github.com/NucleantUI/PyShader.git", .upToNextMinor(from: "0.0.4")),
    ],
    targets: [
        .executableTarget(
            name: "AnimatableShader",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")],
            // The shaders in `pyshader.toml`, compiled to SPIR-V as the app builds.
            plugins: [.plugin(name: "PyShaderBuildPlugin", package: "PyShader")]
        ),
    ]
)
