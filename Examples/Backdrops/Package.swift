// swift-tools-version: 6.2

import PackageDescription
import Foundation

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.0.1"))
//
// Its shader is a PyShader `.py` file compiled to SPIR-V by PyShader's build
// plugin, as listed in `pyshader.toml`: the `.spv` is a resource of the app,
// built with it, and nothing compiles a shader at run time.
//
// PyShader from the sibling checkout under `NUCLEANT_LOCAL_DEV=1`, as
// NucleantUI takes it then — the two have to be the same package.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "Backdrops",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
        localDev
            ? .package(path: "../../../PyShader")
            : .package(url: "https://github.com/NucleantUI/PyShader.git", .upToNextMinor(from: "0.0.4")),
    ],
    targets: [
        .executableTarget(
            name: "Backdrops",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")],
            plugins: [.plugin(name: "PyShaderBuildPlugin", package: "PyShader")]
        ),
    ]
)
