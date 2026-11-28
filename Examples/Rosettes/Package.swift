// swift-tools-version: 6.3

import PackageDescription
import Foundation

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.3.13"))
//
// It draws with the Skia API itself, so it takes NucleantSkia as well: the
// sibling checkout under `NUCLEANT_LOCAL_DEV=1`, its 0.1 releases otherwise —
// the same NucleantSkia NucleantUI draws with.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "Rosettes",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
        localDev
            ? .package(path: "../../../NucleantSkia")
            : .package(url: "https://github.com/NucleantUI/NucleantSkia.git", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .executableTarget(
            name: "Rosettes",
            dependencies: [
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "NucleantSkia", package: "NucleantSkia"),
            ]
        ),
    ]
)
