# Getting started

Add NucleantUI to a Swift package and open your first window.

## Add the package

NucleantUI is a Swift package. Depend on it from your app's `Package.swift`:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/NucleantUI/NucleantUI.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [.product(name: "NucleantUI", package: "NucleantUI")]
        ),
    ]
)
```

The packages NucleantUI is built on — NucleantVulkan, NucleantSkia,
NucleantThorVG and NucleantApplication — come along with it. Shaders written
in Python syntax are PyShader's, which an app adds itself — see
<doc:DrawingWithShaders>.

## Write an app

An app is a type conforming to ``NucleantApp`` whose `body` lists its windows.
A ``WindowGroup`` opens one window over a view:

```swift
import NucleantUI

@main
struct MyApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Hello") {
            Greeting()
        }
        .defaultSize(width: 480, height: 320)
    }
}

@View
struct Greeting {
    var body: some View {
        VStack(spacing: 12) {
            Text("Hello, NucleantUI").font(.title)
            Text("Drawn by Skia, on Vulkan.")
                .foregroundColor(.secondary)
        }
    }
}
```

The body can list more scenes after the first. Only the first opens at
launch; the others open when a view asks for one by its id, with
``EnvironmentValues/openWindow``, or from the menu bar — File › New Window
opens another window from a ``WindowGroup``, and each ``Window`` is listed in
the Window menu:

```swift
var body: some Scene {
    WindowGroup("Hello") {
        Greeting()
    }
    Window("About Hello", id: "about") {
        AboutHello()
    }
}
```

Build and run it like any executable package:

```sh
swift run MyApp
```

On iOS the same `@main` type is the entry point; open the package in Xcode and
pick a device or simulator.

## Learn from the examples

The repository's `Examples` folder has fourteen standalone apps — a
calculator, a task list, a drawing pad, a photo library, an issue tracker, a
drum sampler and more — each its own package you can build and copy from:

```sh
cd Examples/Calculator
swift build && .build/debug/Calculator
```

The <doc:tutorials/NucleantUI> will walk through building several of them.

## Next steps

- <doc:DeclaringViews> — what `@View` does and why every view has it.
- <doc:ManagingState> — `@State`, bindings and `@Observable` models.
- <doc:DrawingWithShaders> — GPU shaders as views.
