//
//  App.swift
//  NucleantUI
//

import NucleantApplication
import NucleantThorVG
import NucleantWindow
import NucleantVulkan
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
import Platform_iOS
#endif
#if os(Linux)
import Glibc
#endif
#if os(Windows)
import ucrt
#endif

/// The entry point of a NucleantUI app.
///
/// ```swift
/// @main
/// struct DemoApp: NucleantApp {
///     var body: some Scene {
///         WindowGroup("Demo") { ContentView() }
///     }
/// }
/// ```
@MainActor
public protocol NucleantApp {
    /// `NucleantRenderNode` unless the app or its protocol says otherwise —
    /// `protocol MyApp: NucleantApp where RenderNode == MyRenderNode {}`. Defaulted
    /// here rather than in an extension: an extension's typealias would win
    /// over the refining protocol's constraint.
    associatedtype RenderNode: NucleantContainerNode = NucleantRenderNode
    associatedtype Body: Scene
    init()

    @SceneBuilder var body: Body { get }
}

extension NucleantApp {
    #if NUCLEANT_PREVIEW
    /// What `@main` calls in a preview build: the app's `@Preview`
    /// functions, one tab each, instead of its scenes (`PreviewRuntime`).
    public static func main() {
        let runtime = PreviewRuntime()
        runtime.setup()
        runtime.run()
    }
    #else
    /// What `@main` calls. Builds the platform application, presents the
    /// scene's windows on launch, and runs the event loop.
    public static func main() {
        let runtime = AppRuntime(app: Self())
        runtime.setup()
        runtime.run()
    }
    #endif
}

/// Knobs the runtime reads at launch. A namespace rather than statics on
/// `AppRuntime`, which is generic and so can't hold stored type properties.
public enum AppRuntimeSettings {
    /// ThorVG worker threads. `0` runs everything on the calling thread, which
    /// is what a GPU canvas wants — the raster workers only help the software
    /// backend. Set before `main()` to override.
    @MainActor public static var thorVGThreadCount: UInt32 = 0

    /// Force every window light or dark instead of following the system.
    /// `nil` — the default — follows it. Set before `main()`; a subtree can
    /// still be fixed the other way with `.colorScheme(_:)`.
    @MainActor public static var colorScheme: ColorScheme? = nil
}

/// Bridges a `NucleantApp` onto `NucleantApplication`, the platform-lifecycle
/// protocol the rest of the Nucleant stack is built around.
@MainActor
public final class AppRuntime<A: NucleantApp>: NucleantApplication {

    private let app: A

    /// Windows are held for the process's lifetime — each owns its engine and
    /// platform window, and `PlatformWindow` only weakly references back.
    private var windows: [HostingWindow<A.RenderNode>] = []

    #if os(macOS)
    /// The GPU device every window renders with: made before the first window
    /// and kept for the process, so a node belongs to the app, not to one
    /// window — any window can show it, and it outlives the one that made it.
    private var renderDevice: VulkanRenderDevice<A.RenderNode>?
    #endif

    public var appDelegate: AppDelegate<AppRuntime<A>>?

    public init(app: A) {
        self.app = app
    }


    public func onStart() {
        // The engine reports what went wrong on stdout, which is fully
        // buffered when the process isn't on a terminal — Xcode's console
        // included — so a failure on a device shows up late or never. Line
        // buffering costs nothing in a GUI app.
        nucleantLineBufferStandardOutput()

        // ThorVG's engine has to be up before any canvas is created —
        // `tvg_wgcanvas_create` returns null otherwise, which is exactly what a
        // missing init looks like from the outside.
        ThorEngine.ensureInitialized(threads: AppRuntimeSettings.thorVGThreadCount)

        windows = app.body._makeWindows()
        #if os(macOS)
        do {
            let device = try VulkanRenderDevice<A.RenderNode>()
            renderDevice = device
            for window in windows {
                window.renderDevice = device
            }
        } catch {
            nucleantLogError("NucleantUI: no GPU device for the windows to share: \(error)\n")
        }
        #endif
        for window in windows {
            do {
                try window.present()
            } catch {
                nucleantLogError("NucleantUI: window present failed: \(error)\n")
            }
        }
        // Always, even with no `.commands`: the standard menus are what give
        // the app Quit, Close and the Edit shortcuts.
        installCommands(self)
    }

    /// Hand control to the platform event loop. Does not return.
    ///
    /// macOS: `setup()` already installed the delegate whose
    /// `applicationDidFinishLaunching` calls `onStart`, so this is just the
    /// run loop. iOS inverts that — `UIApplicationMain` owns the
    /// `UIApplication` and instantiates the delegate *by class name*, so the
    /// runtime can't be the delegate itself (a generic class has no ObjC
    /// name); `_AppLaunchDelegate` stands in and calls back here once a
    /// window scene is connected, which is the earliest `HostingWindow` can
    /// build a scene-owned `UIWindow`.
    public func run() {
        #if os(macOS)
        NSApplication.shared.run()
        #elseif os(iOS)
        // A bare executable — a SwiftPM executable product run on the
        // simulator, rather than an app target — has no bundle, and UIKit
        // aborts on the missing bundle identifier inside UIApplicationMain
        // with nothing to say why. Say why.
        guard Bundle.main.bundleIdentifier != nil else {
            nucleantLogError("""
                NucleantUI: no app bundle (\(Bundle.main.bundlePath)). \
                On iOS run an application target — for the demo, the \
                NucleantUIDemoApp scheme in XcodeExamples — not the \
                package's executable product.

                """)
            exit(1)
        }
        _AppLaunchDelegate.onLaunch = { [self] in onStart() }
        UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            nil,
            NSStringFromClass(_AppLaunchDelegate.self)
        )
        #elseif os(Linux)
        // Linux is macOS's shape, not Android's: the delegate connects to the
        // display server, fires `onStart()` — which is where the windows get
        // presented — and hands this thread to the Wayland/X11 event loop,
        // returning only when the last window closes. Without this branch
        // `main()` returned here and the process exited before a window was
        // ever built, which is what "nothing happens on Linux" was.
        //
        // Straight to the delegate for the same reason as Android below: this
        // declaration shadows NucleantApplication's protocol-extension `run()`,
        // so calling it by name would resolve back here.
        //
        // The one thing neither Apple platform has to say: there may be no
        // display server to talk to — a bare TTY, an SSH shell with nothing
        // forwarded, a container without the socket bind-mounted. Report that
        // as itself rather than as a window that never appears.
        do {
            try appDelegate?.run()
        } catch {
            nucleantLogError("NucleantUI: no display server to open a window on: \(error)\n")
            exit(1)
        }
        #elseif os(Windows)
        // Linux's shape: the delegate makes the process DPI-aware and
        // registers the window class, fires `onStart()`, and hands this
        // thread to the Win32 message loop until the last window closes.
        // Straight to the delegate for the reason Linux gives above.
        do {
            try appDelegate?.run()
        } catch {
            nucleantLogError("NucleantUI: could not start the Win32 app: \(error)\n")
            exit(1)
        }
        #elseif os(Android)
        // Unlike every other platform this returns. The Activity owns the UI
        // thread and the main looper, so there is no event loop here to hand
        // the calling thread to, and the render loop belongs to
        // `PlatformWindow` — started when a surface appears, stopped when it
        // goes away. Keeping the process alive past this point is the
        // bootstrap's job, not this call's.
        //
        // Straight to the delegate rather than NucleantApplication's own
        // Android `run()`: that one is a protocol *extension* method, which
        // this declaration shadows, so calling it by name from here would
        // resolve back to this function. Both do the same one thing.
        appDelegate?.run()
        #elseif os(WASI)
        // Android's shape: this returns. The page owns the event loop, so
        // `main` hands the app to it — the delegate keeps the runtime alive
        // for the page and makes the page's main queue Swift concurrency's
        // executor — presents the windows in `onStart()`, and returns; from
        // then on the module runs when the page calls in, per display
        // refresh and per input event.
        appDelegate?.run()
        #endif
    }
}

extension AppRuntime: WindowCommands {
    /// The scenes' `.commands`, lowered. Evaluated when installed, so the
    /// menu reflects the state the scene body reads at that moment.
    public var menuBar: MenuBar {
        let menuBar = MenuBar()
        app.body._lowerCommands(into: menuBar)
        return menuBar
    }
}

#if os(iOS)
/// The `UIApplicationDelegate` the runtime hands to `UIApplicationMain`.
///
/// It decides *when* the app's windows get presented. With a scene manifest
/// in Info.plist (`UIApplicationSceneManifest`, the default for a modern
/// iOS target) UIKit asks for a scene configuration and the answer names
/// `_AppSceneDelegate`, which presents once its `UIWindowScene` connects —
/// that always happens after `didFinishLaunching`, and a window built from
/// the scene is what tracks Stage Manager resizing. Without a manifest UIKit
/// never connects a scene, so the legacy path presents right away onto a
/// screen-sized frame instead. Either way `onLaunch` fires exactly once.
public final class _AppLaunchDelegate: UIResponder, UIApplicationDelegate {
    /// Set by `AppRuntime.run()` before `UIApplicationMain` takes over.
    nonisolated(unsafe) static var onLaunch: (@MainActor () -> Void)?
    private nonisolated(unsafe) static var launched = false

    static func launchOnce() {
        guard !launched else { return }
        launched = true
        onLaunch?()
    }

    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
            Self.launchOnce()
        }
        return true
    }

    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Built in code rather than named in the plist: the plist would need
        // the mangled `NucleantUI._AppSceneDelegate`, which is the
        // library's business, not the app's.
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = _AppSceneDelegate.self
        return config
    }

    /// UIKit asks the app delegate for the menu bar; the runtime's commands
    /// are waiting in the shared `UIKitMenuBar`.
    public override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        UIKitMenuBar.shared.build(with: builder)
    }
}

/// Records the connecting scene in `ActiveScene.current` — where
/// `HostingWindow.present()` looks for the scene to attach to — then lets
/// the runtime present.
public final class _AppSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        ActiveScene.current = windowScene
        _AppLaunchDelegate.launchOnce()
    }
}
#endif
