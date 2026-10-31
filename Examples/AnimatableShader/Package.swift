// swift-tools-version: 6.2

import PackageDescription
import Foundation

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMajor(from: "0.1.0"))
//
// Its shaders are PyShader `.py` files compiled to SPIR-V by PyShader's build
// plugin, as `pyshader.toml` lists them — PyShader the sibling checkout under
// `NUCLEANT_LOCAL_DEV=1`, its release otherwise.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "AnimatableShader",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
        localDev
            ? .package(path: "../../../PyShader")
            : .package(url: "https://github.com/NucleantUI/PyShader.git", .upToNextMinor(from: "0.0.4")),
    ],
    targets: [
        .executableTarget(
            name: "AnimatableShader",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")],
            plugins: [.plugin(name: "PyShaderBuildPlugin", package: "PyShader")]
        ),
    ]
)
