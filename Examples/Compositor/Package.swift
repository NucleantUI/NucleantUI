// swift-tools-version: 6.2

import PackageDescription
import Foundation

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.0.1"))
//
// Its shader is generated from the layer stack while it runs, so it is
// compiled while it runs too: NucleantUI_PyShader's `PyShaderFunction` — the
// sibling checkout under `NUCLEANT_LOCAL_DEV=1`, its release otherwise.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "Compositor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
        localDev
            ? .package(path: "../../../NucleantUI_PyShader")
            : .package(url: "https://github.com/NucleantUI/NucleantUI_PyShader.git", .upToNextMinor(from: "0.0.1")),
    ],
    targets: [
        .executableTarget(
            name: "Compositor",
            dependencies: [
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "NucleantUI_PyShader", package: "NucleantUI_PyShader"),
            ]
        ),
    ]
)
