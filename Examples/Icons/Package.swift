// swift-tools-version: 6.2

import PackageDescription

// A standalone app built on NucleantUI. The library is taken from the
// enclosing checkout; in your own project replace the path dependency with
//   .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.1.0"))
//
// The icons under Sources/Icons/Material are eight categories of Google's
// Material Icons (https://github.com/google/material-design-icons, Apache
// License 2.0), each in its five styles, copied as SVG files. They are a
// resource of the app, loaded through `Bundle.module`.
let package = Package(
    name: "Icons",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Icons",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")],
            resources: [.copy("Material")]
        ),
    ]
)
