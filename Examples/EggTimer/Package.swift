// swift-tools-version: 6.3

import PackageDescription

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master")
//
// It lives in the system tray, which a desktop has: macOS, Windows and
// Linux. On iOS and Android there is no tray, and so nothing to show.
let package = Package(
    name: "EggTimer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "EggTimer",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")]
        ),
    ]
)
