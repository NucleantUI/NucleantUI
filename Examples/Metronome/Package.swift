// swift-tools-version: 6.3

import PackageDescription
import Foundation

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master")
//
// Its sound goes through NucleantAudio, a package of its own: the sibling
// checkout under `NUCLEANT_LOCAL_DEV=1`, its 0.0 releases otherwise.
let localDev = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

let package = Package(
    name: "Metronome",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
        localDev
            ? .package(path: "../../../NucleantAudio")
            : .package(url: "https://github.com/NucleantUI/NucleantAudio.git", .upToNextMinor(from: "0.0.0")),
    ],
    targets: [
        .executableTarget(
            name: "Metronome",
            dependencies: [
                .product(name: "NucleantUI", package: "NucleantUI"),
                .product(name: "NucleantAudio", package: "NucleantAudio"),
            ]
        ),
    ]
)
