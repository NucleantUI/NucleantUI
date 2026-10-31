// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport
import Foundation

// MARK: - Target platform

/// WebAssembly (`swift build --swift-sdk <version>_wasm`) is a cross-compile
/// from any host, so — like Android below — an explicit opt-in, the one every
/// Nucleant package reads: NucleantApplication declares `Platform_Wasm` and
/// its `Dispatch` stand-in only under it.
let isWasm = ProcessInfo.processInfo.environment["WASM_BUILD"] == "1"

// MARK: - Primary renderer

/// Which backend's canvases the views' display list is drawn into — the
/// window canvas, `.drawingGroup()`, the per-view painter and the `.shader`
/// layers. `true` defines `SKIA_MODE`, which compiles
/// `App/CanvasBackend+Skia.swift` (Skia nodes, `SkiaDisplayRenderer`);
/// `false` compiles `App/CanvasBackend+Thor.swift` (ThorVG nodes,
/// `ThorDisplayRenderer`) instead. Exactly one is in a build, and the code
/// above them names neither. `ThorCanvas` views keep their own ThorVG nodes
/// in both (`App/ThorCanvasNodes.swift`); text is measured through ThorVG
/// in both.
///
/// Skia by default. `NUCLEANT_SKIA_MODE=1|0` in the environment wins.
/// (SwiftPM caches the evaluated manifest, but re-evaluates it when the
/// environment it read changes.)
let skiaMode: Bool = {
    if let flag = ProcessInfo.processInfo.environment["NUCLEANT_SKIA_MODE"] {
        return ["1", "true", "yes"].contains(flag.lowercased())
    }
    return true
}()

// MARK: - Dependency source

/// Build against the sibling checkouts (`../NucleantVulkan` etc.) or
/// each repo's releases on GitHub (`nucleantDependencies()`).
///
/// GitHub unless `NUCLEANT_LOCAL_DEV=1` is in the environment: the sibling
/// checkouts are used only when that turns them on, never just because they
/// are there. Every Nucleant package reads the same variable, so one setting
/// covers the whole chain.
let localDev: Bool = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

/// The Nucleant packages this one is built on, from wherever
/// `localDev` says. Product names and `package:` identities are the same
/// either way — SwiftPM derives a path dependency's identity from the
/// directory name and a URL dependency's from the repository name, and those
/// match — so the targets below never need to know which source is in use.
/// Android is always a cross-compile: `Package.swift` is evaluated by the *host*
/// toolchain, so `#if os(Android)` here would describe the host and never be
/// true. NucleantApplication only declares its `Platform_Android` product under
/// the same env opt-in, so referencing that product unconditionally would break
/// every non-Android resolve — the two manifests have to agree on the signal.
let isAndroid = ProcessInfo.processInfo.environment["SWIFT_ANDROID_HOME"] != nil
    || ProcessInfo.processInfo.environment["ANDROID_BUILD"] != nil

/// Linux is the mirror image: NucleantApplication declares `Platform_Linux`
/// only when it is being built *on* Linux, because that provider's CWayland
/// target compiles wayland-scanner output against <wayland-client.h>, which no
/// Apple SDK has — so naming the product unconditionally would break every
/// Apple resolve, the same way naming Platform_Android does. Unlike Android
/// there is no cross-compile into Linux, so a host check is the target check.
/// `&& !isAndroid` because the Android host *is* Linux.
#if os(Linux)
let isLinux = !isAndroid && !isWasm
#else
let isLinux = false
#endif

/// Windows the same way: NucleantApplication declares `Platform_Windows` only
/// when built on Windows, which is native like Linux, so the host is the
/// target.
#if os(Windows)
let isWindows = true
#else
let isWindows = false
#endif

/// The platform provider NucleantUI links directly, for the
/// `PlatformWindow` that `HostingWindow` owns. Only one is ever in scope.
func platformProviders() -> [Target.Dependency] {
    var deps: [Target.Dependency] = [
        .product(name: "Platform_MacOS", package: "NucleantApplication", condition: .when(platforms: [.macOS])),
        .product(name: "Platform_iOS", package: "NucleantApplication", condition: .when(platforms: [.iOS])),
    ]
    if isLinux {
        deps.append(.product(name: "Platform_Linux", package: "NucleantApplication", condition: .when(platforms: [.linux])))
    }
    if isWindows {
        deps.append(.product(name: "Platform_Windows", package: "NucleantApplication", condition: .when(platforms: [.windows])))
    }
    if isAndroid {
        deps.append(.product(name: "Platform_Android", package: "NucleantApplication", condition: .when(platforms: [.android])))
        // The Java edge (jextract's `org.nucleantui.NucleantBridge`). Linked in
        // here rather than declared by every app, so an Android app's package
        // names NucleantUI and nothing else — the same way it does not
        // name Platform_Android.
        deps.append(.product(name: "NucleantBridge", package: "NucleantApplication", condition: .when(platforms: [.android])))
    }
    if isWasm {
        deps.append(.product(name: "Platform_Wasm", package: "NucleantApplication", condition: .when(platforms: [.wasi])))
        // libdispatch's API in the browser — the wasm Swift SDK has none —
        // for the framework's `import Dispatch`.
        deps.append(.product(name: "Dispatch", package: "NucleantApplication", condition: .when(platforms: [.wasi])))
    }
    return deps
}

func nucleantDependencies() -> [Package.Dependency] {
    if localDev {
        return ["NucleantVulkan", "NucleantThorVG", "NucleantApplication", "NucleantSkia"]
            .map { .package(path: "../\($0)") }
    }
    // Each by version, up to its next major: its new 0.x releases from 0.1.0
    // (the shared VulkanRenderDevice) are picked up as they come. (Never by
    // branch: a package depended on by version may not have one, so
    // NucleantUI could not be.)
    return [
        .package(url: "https://github.com/NucleantUI/NucleantVulkan.git", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/NucleantUI/NucleantThorVG.git", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/NucleantUI/NucleantApplication.git", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/NucleantUI/NucleantSkia.git", .upToNextMajor(from: "0.1.0")),
    ]
}

/// The layout / input / perf traces (`LayoutTrace`, `InputTrace`,
/// `PerfTrace`) are compiled in only with `NUCLEANT_TRACE=1` in the
/// environment; each is then switched on by its own variable at run time.
/// Left out, nothing of them is checked or counted on a frame.
let traceBuild = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_TRACE"] ?? "").lowercased()
)

/// `#if SKIA_MODE` / `#if NUCLEANT_TRACE` in the framework and its tests.
let skiaModeSettings: [SwiftSetting] = (skiaMode ? [.define("SKIA_MODE")] : [])
    + (traceBuild ? [.define("NUCLEANT_TRACE")] : [])

let package = Package(
    name: "NucleantUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "NucleantUI", targets: ["NucleantUI"]),
        .library(name: "NucleantAudio", targets: ["NucleantAudio"]),
        .executable(name: "NucleantUIDemo", targets: ["NucleantUIDemo"]),
        .executable(name: "ExperimentalUITests", targets: ["ExperimentalUITests"]),
    ],
    dependencies: nucleantDependencies() + [
        // Pinned to the version the sibling packages already resolve, so the
        // toolchain's prebuilt swift-syntax is used instead of a source build.
        // 603 rather than 602: swift-java 0.4.2 — which the Android bootstrap
        // needs, because 0.1.2 does not compile on Swift 6.3.3 — requires it,
        // and an `exact:` pin here decides the version for the whole graph.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        // Compiler plugin behind `@View` and `#viewID`. Runs at build time only;
        // nothing from swift-syntax ends up in the framework.
        .macro(
            name: "NucleantUIMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The bounds of the linker section `@Preview` records live in,
        // which only C can name (Preview/PreviewRuntime.swift).
        .target(name: "CNucleantPreview"),
        .target(
            name: "NucleantUI",
            dependencies: [
                "NucleantUIMacros",
                "CNucleantPreview",
                .product(name: "NucleantVulkan", package: "NucleantVulkan"),
                .product(name: "NucleantShader", package: "NucleantVulkan"),
                .product(name: "NucleantThorVG", package: "NucleantThorVG"),
                .product(name: "NucleantApplication", package: "NucleantApplication"),
                .product(name: "NucleantWindow", package: "NucleantApplication"),
                .product(name: "NucleantSkia", package: "NucleantSkia"),
            ] + platformProviders(),
            // The default faces (Roboto, Roboto Mono) travel with the library,
            // so text looks the same on every platform and never depends on
            // what fonts the OS happens to ship — see FontRegistry.
            resources: [.copy("Resources/Fonts")],
            swiftSettings: skiaModeSettings
        ),
        // Audio file loading and playback. Stands on its own — no NucleantUI
        // dependency — so an app, or NucleantDSP later, can use it without the
        // UI. One shared API; each platform's implementation lives in its own
        // `+<Platform>.swift` file.
        .target(name: "NucleantAudio"),
        .executableTarget(
            name: "NucleantUIDemo",
            dependencies: ["NucleantUI", .product(name: "NucleantThorVG", package: "NucleantThorVG")],
            // PyShader sources and the `.spv` each was compiled to (the
            // command is in its header): the demo runs SPIR-V, as NucleantUI
            // does, with no compiler in it.
            resources: [.copy("Shaders")]
        ),
        .testTarget(
            name: "NucleantUITests",
            dependencies: ["NucleantUI", .product(name: "NucleantSkia", package: "NucleantSkia")],
            // Precompiled modules beside the `.py` each was compiled from.
            resources: [.copy("Fixtures")],
            // NUCLEANT_PREVIEW: the tests' `@Preview` functions leave their
            // records, as an app's do in a preview build (PreviewTests).
            swiftSettings: skiaModeSettings + [.define("NUCLEANT_PREVIEW")]
        ),
        .executableTarget(
            name: "ExperimentalUITests",
            dependencies: ["NucleantUI", .product(name: "NucleantThorVG", package: "NucleantThorVG")]
        ),
    ] + macroTestTargets()
)

/// What `@State` expands to, and what it refuses, checked on the syntax — no
/// framework involved.
///
/// Not in a wasm build. A test product holding a macro's tests is built for
/// the build machine as well (that is where a macro runs), and SwiftPM decides
/// so without looking at a dependency's platform condition. Built there, the
/// framework meets wasm's CVulkan, which is empty off wasm, and the tests the
/// browser runs never get built.
func macroTestTargets() -> [Target] {
    guard !isWasm else { return [] }
    return [
        .testTarget(
            name: "NucleantUIMacrosTests",
            dependencies: [
                "NucleantUIMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
}
