//
//  HostingWindow.swift
//  NucleantUI
//
//  A `NucleantWindow` that owns a platform window, a Vulkan engine and one
//  window-filling canvas, and drives a `ViewHost` from the display link.
//
//  `NucleantWindow` and `WindowBaseDelegate` are non-isolated protocols, so the
//  witnesses here are non-isolated too; every one of them is in fact called on
//  the main thread (AppKit event dispatch, the display link), which is what
//  `MainActor.assumeIsolated` asserts before touching the host.
//

import NucleantVulkan
import NucleantWindow
import Foundation
import NucleantSkia

#if os(macOS)
import AppKit
import Platform_MacOS
#endif
#if os(iOS)
import UIKit
import Platform_iOS
// `ActiveScene` — the connected `UIWindowScene` the window attaches to.
import NucleantApplication
#endif
#if os(Android)
import Platform_Android
#endif
#if os(Linux)
import Platform_Linux
// VkExtent2D — Linux has no CAMetalLayer whose drawable size the engine can
// read, so the swapchain size is supplied as a callback instead.
import CVulkan
#endif
#if os(WASI)
import Platform_Wasm
#endif
#if os(Windows)
import Platform_Windows
// VkExtent2D, for the swapchain-size callback as on Linux; GetKeyState, for
// the modifiers a press is made with.
import CVulkan
import WinSDK
#endif

#if os(macOS)
/// Where the next window's top-left corner goes, so windows opened one after
/// another cascade instead of piling up at the centre. `nil` until the first
/// window opens, which stays centred. At file scope: a generic class has no
/// stored statics.
@MainActor
private var nextCascadePoint: NSPoint?
#endif

public final class HostingWindow<Node: NucleantContainerNode>: NucleantWindow, @unchecked Sendable {

    //public typealias Node = NucleantRenderNode

    public var renderEngine: VulkanRenderEngine<Node>?

    #if os(macOS)
    /// The app's device, which the engine is built on when the window is
    /// presented. Without one the engine makes a device of its own.
    var renderDevice: VulkanRenderDevice<Node>?
    #endif

    /// (x, y, width, height) in *pixels*, like every other Nucleant window.
    public var win_rect: SIMD4<Int>

    let title: String

    /// The view tree. Isolated to the main actor; every access below goes
    /// through `assumeIsolated`.
    let host: ViewHost

    /// The window's input as its views reach it (`\.windowInput`): its
    /// delegate hears what none of `host`'s views takes.
    let input: WindowInput

    /// The presses the input delegate took — their moves and releases are
    /// its, wherever they go: the mouse's left and right buttons, and
    /// fingers by id.
    private var delegateHasMouse = false
    private var delegateHasRightMouse = false
    private var delegateTouches: Set<Int> = []

    #if os(macOS) || os(iOS) || os(Android) || os(Linux) || os(WASI) || os(Windows)
    /// Strongly held: `PlatformWindow` keeps only a weak `win_delegate` back
    /// here, so the window's lifetime is this object's to own.
    var platformWindow: PlatformWindow<HostingWindow>?
    #endif

    #if os(macOS)
    /// Held here: an `NSResponder`'s `nextResponder` link is unretained.
    private var editCommandResponder: EditCommandResponder?
    #endif

    /// GPU slots for `Shader` views — one per live shader, composited into the
    /// view's own rect rather than into the shared canvas.
    private var shaderSlots: ShaderSlotRegistry<Node>?

    /// Where the pointer last was, in points — shaders get it as a uniform.
    private var pointerLocation: Point = .zero

    /// The window's canvas, filling the swapchain — in this build's backend
    /// (`CanvasBackend`). Its container is the engine slot the canvas is
    /// bound to, held so a repaint can re-arm it directly; its id also keys
    /// every engine-side map, so a resize names the same one it was appended
    /// with.
    private var windowCanvas: RenderNodeManager<Node>.CanvasNode?

    /// Backing-store pixels per point. Layout is in points; the renderer scales.
    private var displayScale: Double = 1

    #if os(macOS)
    /// Follows the app's effective appearance — System Settings, or a
    /// per-app override — for as long as the window lives.
    private var appearanceObservation: NSKeyValueObservation?
    #endif

    #if os(WASI)
    /// Follows the page's `prefers-color-scheme` for as long as the window
    /// lives; the id `BrowserAppearance` handed out for it.
    private var appearanceObserver: Int?

    deinit {
        if let appearanceObserver { BrowserAppearance.removeObserver(appearanceObserver) }
    }
    #endif

    #if os(Windows)
    /// Follows the app mode (light or dark) for as long as the window lives;
    /// the id `WindowsAppearance` handed out for it.
    private var appearanceObserver: Int?

    deinit {
        if let appearanceObserver { WindowsAppearance.removeObserver(appearanceObserver) }
    }
    #endif


    /// The scene's say in this window's size — `defaultSize`,
    /// `windowResizability`, `windowIdealSize` — filled in by the scene's
    /// modifiers before the window is presented.
    var sizing = WindowSizing()

    /// Held at the size it was created with rather than sized by the
    /// platform, where the platform would otherwise decide: a browser page,
    /// which a window fills by default.
    private let holdsCreatedSize: Bool

    /// A window whose size its scene decides, through `sizing`.
    @MainActor
    public init<Root: View>(title: String, root: Root) {
        self.title = title
        self.win_rect = SIMD4(0, 0, 0, 0)
        self.host = ViewHost(root: root)
        self.input = WindowInput()
        host.environment.windowInput = input
        self.holdsCreatedSize = false
    }

    /// A window of a set size: its default size on a desktop, and in a
    /// browser the size the canvas keeps instead of filling the page.
    @MainActor
    public init<Root: View>(title: String, width: Double, height: Double, root: Root) {
        self.title = title
        self.win_rect = SIMD4(0, 0, Int(width), Int(height))
        self.host = ViewHost(root: root)
        self.input = WindowInput()
        host.environment.windowInput = input
        self.holdsCreatedSize = true
        self.sizing.defaultSize = Size(width: width, height: height)
    }

    // MARK: - Bring-up

    public func present() throws {
        try MainActor.assumeIsolated {
            // The size the window opens at, before its content has said
            // anything about limits; the platforms that size the window
            // themselves replace it.
            let size = sizing.defaultSize ?? WindowSizing.fallbackSize
            win_rect = SIMD4(0, 0, Int(size.width), Int(size.height))
            #if os(macOS)
            try presentMacOS()
            #elseif os(iOS)
            try presentIOS()
            #elseif os(Android)
            presentAndroid()
            #elseif os(Linux)
            try presentLinux()
            #elseif os(WASI)
            try presentBrowser()
            #elseif os(Windows)
            try presentWindows()
            #else
            throw HostingWindowError.unsupportedPlatform
            #endif
        }
    }

    // MARK: - Closing

    /// Told once the window has closed — its close button, File › Close,
    /// `dismissWindow` — after the platform is done closing it, so what
    /// lets go of the window last doesn't do it from inside that.
    var onClose: (@MainActor () -> Void)?

    /// The platform closed the window.
    @MainActor
    func didClose() {
        onClose?()
        onClose = nil
    }

    /// Close the window, as its close button does. One never put on screen
    /// has nothing for the platform to close, and is closed at once.
    @MainActor
    func close() {
        #if os(macOS)
        if let platformWindow {
            platformWindow.close()
            return
        }
        #else
        if renderEngine != nil {
            nucleantLogError("NucleantUI: closing a window from the app is not wired on this platform yet\n")
            return
        }
        #endif
        didClose()
    }

    /// Whether the app can have more than one window open on this platform:
    /// macOS's. Elsewhere so far, the app's first window is the one it has.
    static var supportsMultipleWindows: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Bring the window in front of the app's others, and give it the keys.
    @MainActor
    func bringToFront() {
        #if os(macOS)
        platformWindow?.makeKeyAndOrderFront(nil)
        #else
        nucleantLogError("NucleantUI: bringing a window to the front is not wired on this platform yet\n")
        #endif
    }

    /// The scheme the window shows: the app's override if it set one, else
    /// what the system says.
    @MainActor
    private static func systemColorScheme() -> ColorScheme {
        if let forced = AppRuntimeSettings.colorScheme { return forced }
        #if os(macOS)
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
        #elseif os(iOS)
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        #elseif os(Android)
        // `Configuration.uiMode`, which the Activity sends before the app
        // starts and on every change — see AndroidSurfaceHost.
        return AndroidSurfaceHost.isNightMode ? .dark : .light
        #elseif os(Linux)
        // The desktop's own setting, through the XDG portal — see
        // DesktopAppearance. A desktop with no preference gets light, the same
        // answer as a platform with nothing to ask.
        return DesktopAppearance.colorScheme() == .dark ? .dark : .light
        #elseif os(WASI)
        // The page's `prefers-color-scheme` — see BrowserAppearance.
        return BrowserAppearance.colorScheme() == .dark ? .dark : .light
        #elseif os(Windows)
        // The app mode, Settings › Personalization › Colors — see
        // WindowsAppearance.
        return WindowsAppearance.colorScheme() == .dark ? .dark : .light
        #else
        return .light
        #endif
    }

    /// Put `scheme` into the root environment, paint the window's clear
    /// color to match, and rebuild everything — every dynamic color on
    /// screen resolves differently now.
    @MainActor
    private func applyColorScheme(_ scheme: ColorScheme) {
        guard host.environment.colorScheme != scheme || renderEngine.map({ $0.clearColor.a == 0 }) == true else { return }
        host.environment.colorScheme = scheme
        paintClearColor()
        host.invalidate()
        markNeedsRedraw()
    }

    /// The engine's clear color, for the scheme the window shows — the
    /// window's background wherever no view paints one.
    ///
    /// Also for an engine built after the scheme was applied, which starts
    /// with a clear color of its own: on Android every surface gets a new
    /// one, the first included, so without this the window shows the
    /// engine's near-black under light-scheme content.
    @MainActor
    private func paintClearColor() {
        let background = BackgroundStyle().colors.color(for: host.environment.colorScheme)
        renderEngine?.clearColor = (background.red, background.green, background.blue, 1)
    }

    #if os(macOS)
    @MainActor
    private func presentMacOS() throws {
        // 1. Platform window + its CAMetalLayer-backed view. Its display link
        //    starts immediately and no-ops until `win_delegate` and the engine
        //    below are in place.
        let platformWindow = PlatformWindow<HostingWindow>(
            contentRect: NSRect(
                x: Double(win_rect.x),
                y: Double(win_rect.y),
                width: Double(win_rect.z),
                height: Double(win_rect.w)
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // 2. The Vulkan engine renders into that layer, on the app's device.
        let engine = if let renderDevice {
            try VulkanRenderEngine<Node>(device: renderDevice, metalLayer: platformWindow.metalLayer)
        } else {
            try VulkanRenderEngine<Node>(metalLayer: platformWindow.metalLayer)
        }
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self
        // This object holds the window; AppKit releasing it as well on close
        // would release it once too often.
        platformWindow.isReleasedWhenClosed = false
        platformWindow.on_close = { [weak self] in
            // Mid-close, from inside AppKit: the window goes once it's done.
            DispatchQueue.main.async {
                self?.didClose()
            }
        }

        displayScale = Double(platformWindow.metalLayer.contentsScale)

        // 3. One window-filling canvas for the whole tree.
        attachCanvas(engine: engine, width: win_rect.z, height: win_rect.w)

        // 4. Light or dark, now and whenever the system changes its mind.
        applyColorScheme(Self.systemColorScheme())
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // AppKit posts this on the main thread.
            MainActor.assumeIsolated {
                self?.applyColorScheme(Self.systemColorScheme())
            }
        }

        // 5. Show it.
        platformWindow.title = title
        // A window built from a bare `contentRect` sits at the screen's
        // bottom-left corner (AppKit's origin), which on a multi-display setup
        // is easy to lose entirely. Centre it, as a freshly opened document
        // window would be — and each one after it down and to the right of
        // the last, as AppKit cascades, rather than on top of it.
        platformWindow.center()
        nextCascadePoint = platformWindow.cascadeTopLeft(from: nextCascadePoint ?? .zero)
        platformWindow.makeKeyAndOrderFront(nil)
        platformWindow.makeFirstResponder(platformWindow.contentView)
        // The Edit menu's actions, for the view in the tree that has the keys.
        if let contentView = platformWindow.contentView {
            let responder = EditCommandResponder(host: host)
            responder.insert(after: contentView)
            editCommandResponder = responder
        }

        // 6. Seed the size. AppKit posts `windowDidResize` only for actual
        //    resizes, so without this the tree never learns how big it is.
        if let size = platformWindow.contentView?.bounds.size {
            on_size(w: Double(size.width), h: Double(size.height))
        }

        // 7. The window's limits, from its content, once it has been built.
        followContentSizeLimits()
    }

    /// Hold the window to its content's size limits — the minimum and
    /// maximum `windowResizability` asks for, the zoom size
    /// `windowIdealSize` does — and bring it into them when it is outside.
    @MainActor
    private func applyContentSizeLimits(_ limits: ContentSizeLimits) {
        guard let platformWindow else { return }
        let unlimited = CGFloat.greatestFiniteMagnitude
        let minimum = limits.minimum ?? .zero
        let maximum = limits.maximum ?? Size(width: .infinity, height: .infinity)
        platformWindow.contentMinSize = NSSize(width: minimum.width, height: minimum.height)
        platformWindow.contentMaxSize = NSSize(
            width: maximum.width.isFinite ? max(maximum.width, minimum.width) : unlimited,
            height: maximum.height.isFinite ? max(maximum.height, minimum.height) : unlimited
        )
        // Nothing to drag between: no resize handles, and no zoom button.
        if limits.isFixed {
            platformWindow.styleMask.remove(.resizable)
        } else {
            platformWindow.styleMask.insert(.resizable)
        }
        platformWindow.zoomContentSize = sizing.zoomSize(for: limits).map {
            NSSize(width: $0.width, height: $0.height)
        }

        // A window opened smaller than its content allows — the default size
        // under the minimum — grows to it, keeping its title bar in place.
        guard let current = platformWindow.contentView?.bounds.size else { return }
        let clamped = WindowSizing.clamp(Size(width: Double(current.width), height: Double(current.height)), to: limits)
        guard clamped.width != Double(current.width) || clamped.height != Double(current.height) else { return }
        var frame = platformWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: clamped.width, height: clamped.height))
        frame.origin = NSPoint(x: platformWindow.frame.minX, y: platformWindow.frame.maxY - frame.height)
        platformWindow.setFrame(frame, display: true)
    }
    #endif

    #if os(macOS) || os(WASI)
    /// Measure the content's size limits from here on, as the scene's sizing
    /// asks, and hold the window to them each time they change.
    @MainActor
    private func followContentSizeLimits() {
        host.measuredContentSizes = sizing.measurements
        host.onContentSizeLimitsChange = { [weak self] limits in
            self?.applyContentSizeLimits(limits)
        }
    }
    #endif

    #if os(iOS)
    @MainActor
    private func presentIOS() throws {
        // iOS ignores the requested size: the connecting scene's bounds are the
        // window, in normal mode and under Stage Manager alike.
        let scale = Double(ActiveScene.current?.screen.scale ?? 2.0)
        let bounds = ActiveScene.current?.coordinateSpace.bounds ?? UIScreen.main.bounds
        win_rect = SIMD4(
            Int(bounds.origin.x), Int(bounds.origin.y),
            Int(bounds.width * scale), Int(bounds.height * scale)
        )

        let platformWindow: PlatformWindow<HostingWindow>
        if let windowScene = ActiveScene.current {
            platformWindow = PlatformWindow<HostingWindow>(windowScene: windowScene)
        } else {
            platformWindow = PlatformWindow<HostingWindow>(frame: bounds)
        }

        let engine = try VulkanRenderEngine<Node>(metalLayer: platformWindow.metalLayer)
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self
        displayScale = Double(platformWindow.metalLayer.contentsScale)
        // A finger has no scroll wheel, and no right button.
        host.scrollsOnDrag = true
        host.opensContextMenuOnLongPress = true
        // Text is typed on the on-screen keyboard `syncSoftKeyboard` asks for.
        host.hasSoftKeyboard = true
        // Seeded once; a later appearance change is not tracked on iOS yet.
        defer { applyColorScheme(Self.systemColorScheme()) }

        attachCanvas(engine: engine, width: win_rect.z, height: win_rect.w)

        platformWindow.makeKeyAndVisible()
        // Points here — `on_size` applies the scale itself, and `win_rect`
        // above is already in pixels.
        on_size(w: Double(bounds.width), h: Double(bounds.height))
    }
    #endif

    #if os(Linux)
    @MainActor
    private func presentLinux() throws {
        // 1. A Wayland or X11 toplevel, whichever `LinuxSession.detect()` says
        //    the session is. Its frame loop starts in init and no-ops until
        //    `win_delegate` and the engine below are in place, exactly as the
        //    display link does on macOS.
        let platformWindow = try PlatformWindow<HostingWindow>(
            width: win_rect.z,
            height: win_rect.w,
            title: title
        )

        // 2. The engine renders through VK_KHR_wayland_surface or
        //    VK_KHR_xcb_surface, from whichever raw handles the active backend
        //    hands over — there is no layer object to pass, and no drawable to
        //    ask for a size, so the swapchain reads `bufferWidth/Height`
        //    through this callback whenever it recreates itself. Weak, because
        //    the engine is owned by this window and outlives nothing.
        let getExtent: () -> VkExtent2D = { [weak platformWindow] in
            VkExtent2D(
                width: platformWindow?.bufferWidth ?? 0,
                height: platformWindow?.bufferHeight ?? 0
            )
        }
        let engine: VulkanRenderEngine<Node>
        switch platformWindow.vulkanSurfaceKind {
        case .wayland(let display, let surface):
            engine = try VulkanRenderEngine<Node>(
                waylandDisplay: display,
                waylandSurface: surface,
                getExtent: getExtent
            )
        case .xcb(let connection, let window):
            engine = try VulkanRenderEngine<Node>(
                xcbConnection: connection,
                xcbWindow: window,
                getExtent: getExtent
            )
        }
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self

        displayScale = platformWindow.scale

        // 3. One window-filling canvas for the whole tree, in pixels.
        attachCanvas(engine: engine, width: win_rect.z, height: win_rect.w)

        // 4. Light or dark, from the desktop. Neither Wayland nor X11 carries
        //    this — it is a desktop setting, not a display-server one — so it
        //    comes from the XDG portal, which is where every other toolkit
        //    reads it. Seeded once: the portal will also *signal* a change,
        //    which macOS follows through `effectiveAppearance` but this does
        //    not yet.
        applyColorScheme(Self.systemColorScheme())

        // 5. Show it. On X11 this is the real `xcb_map_window`; on Wayland a
        //    window only becomes visible on its first attached buffer, so it is
        //    the frame loop below that actually puts it on screen.
        platformWindow.show()

        // 6. Seed the size. Both backends report a resize only when one
        //    happens — a WM that honours the requested size never sends
        //    one — so without this the tree never learns how big it is.
        //    Points, which is what the backends report and what `on_size`
        //    scales itself; `win_rect` is already in pixels.
        on_size(w: platformWindow.width, h: platformWindow.height)
    }
    #endif

    #if os(WASI)
    @MainActor
    private func presentBrowser() throws {
        // 1. A <canvas> on the page, sized in CSS pixels — the browser's
        //    points. Its requestAnimationFrame ticks start in init and no-op
        //    until `win_delegate` and the engine below are in place, as the
        //    display link does on macOS.
        let platformWindow = try PlatformWindow<HostingWindow>(
            width: win_rect.z,
            height: win_rect.w,
            title: title
        )

        // 2. The engine renders onto that canvas through
        //    VK_NUCLEANT_webgpu_surface — Vulkan on the page's WebGPU. Like
        //    Linux there is no layer to read a drawable size from, so the
        //    swapchain asks for the canvas's drawing buffer, in device
        //    pixels, whenever it recreates itself.
        let engine = try VulkanRenderEngine<Node>(canvasSelector: platformWindow.canvasSelector) { [weak platformWindow] in
            (Int(platformWindow?.bufferWidth ?? 0), Int(platformWindow?.bufferHeight ?? 0))
        }
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self

        displayScale = platformWindow.scale

        // 3. One window-filling canvas for the whole tree.
        attachCanvas(engine: engine, width: win_rect.z, height: win_rect.w)

        // 4. Light or dark, now and whenever the page's preference changes —
        //    the OS setting, or the browser's own theme where that overrides it.
        applyColorScheme(Self.systemColorScheme())
        appearanceObserver = BrowserAppearance.addObserver { [weak self] _ in
            // The page calls in on the main thread; there is no other.
            MainActor.assumeIsolated {
                self?.applyColorScheme(Self.systemColorScheme())
            }
        }

        // 5. Keys go to the canvas.
        platformWindow.show()

        // 6. Seed the size: the page's layout decides the canvas's real size,
        //    and reports it only when it changes. Points, which `on_size`
        //    scales itself.
        on_size(w: platformWindow.width, h: platformWindow.height)

        // 7. The page is the window's screen: the canvas fills it and follows
        //    the browser window, within the limits its content sets once it
        //    has been built. The default size was only where it started.
        if !holdsCreatedSize {
            platformWindow.setLayout(fillsContainer: true)
            followContentSizeLimits()
        }
    }

    /// Hold the canvas to its content's size limits: below the minimum the
    /// page scrolls, past the maximum the canvas stops growing. Zooming is
    /// not something a page does, so the ideal size has no say.
    @MainActor
    private func applyContentSizeLimits(_ limits: ContentSizeLimits) {
        let minimum = limits.minimum ?? .zero
        let maximum = limits.maximum ?? Size(width: .infinity, height: .infinity)
        platformWindow?.setLayout(
            fillsContainer: true,
            minSize: SIMD2(minimum.width, minimum.height),
            maxSize: SIMD2(max(maximum.width, minimum.width), max(maximum.height, minimum.height))
        )
    }
    #endif

    #if os(Windows)
    @MainActor
    private func presentWindows() throws {
        // 1. A Win32 window whose content is the size asked for, in points at
        //    the DPI of the monitor it opens on. Its frame loop runs from init
        //    and no-ops until `win_delegate` and the engine below are in
        //    place, as the display link does on macOS.
        let platformWindow = try PlatformWindow<HostingWindow>(
            width: win_rect.z,
            height: win_rect.w,
            title: title
        )

        // 2. The engine renders through VK_KHR_win32_surface. As on Linux
        //    there is no drawable to ask for a size, so the swapchain reads
        //    the client area, in pixels, through this callback whenever it
        //    recreates itself.
        let engine = try VulkanRenderEngine<Node>(
            win32Instance: platformWindow.win32Instance,
            win32Window: platformWindow.win32Window,
            getExtent: { [weak platformWindow] in
                VkExtent2D(
                    width: platformWindow?.bufferWidth ?? 0,
                    height: platformWindow?.bufferHeight ?? 0
                )
            }
        )
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self

        displayScale = platformWindow.scale

        // 3. One window-filling canvas for the whole tree, in pixels.
        attachCanvas(engine: engine, width: Int(platformWindow.bufferWidth), height: Int(platformWindow.bufferHeight))

        // 4. Light or dark, now and whenever the app mode is switched.
        applyColorScheme(Self.systemColorScheme())
        appearanceObserver = WindowsAppearance.addObserver { [weak self] _ in
            // Announced to the window procedure, on the main thread.
            MainActor.assumeIsolated {
                self?.applyColorScheme(Self.systemColorScheme())
            }
        }

        // 5. Show it.
        platformWindow.show()

        // 6. Seed the size: Windows reports a resize only when one happens.
        //    Points, which `on_size` scales itself.
        on_size(w: platformWindow.width, h: platformWindow.height)
    }
    #endif

    #if os(Android)
    /// Attach to the Activity's surface.
    ///
    /// Inverted from the Apple platforms: there, this creates a window and then
    /// an engine for it. Android gives the app exactly one surface, owned by the
    /// Activity and often created before this code runs at all, so
    /// `PlatformWindow` builds the engine itself the moment a surface is
    /// available — and does it again whenever the surface is replaced, which
    /// happens on every background/resume. The canvas is therefore bound in
    /// `on_surface_recreated()` rather than here; by the time `present()`
    /// returns, that may already have been called.
    ///
    /// Non-throwing for the same reason: there is nothing to fail here. A
    /// surface that has not arrived yet is the normal case, not an error.
    @MainActor
    private func presentAndroid() {
        let platformWindow = PlatformWindow<HostingWindow>()
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self

        // Android has no pointer: the same two gestures iOS substitutes.
        host.scrollsOnDrag = true
        // Text is typed on the soft keyboard `syncSoftKeyboard` asks for.
        host.hasSoftKeyboard = true
        host.opensContextMenuOnLongPress = true
        // Points-to-pixels, from the display. Android reports it as
        // `DisplayMetrics.density` and only Java can read it, so the Activity
        // hands it over before the app starts — see AndroidSurfaceHost. The
        // surface size arrives in pixels, so this is what turns it into the
        // points the layout works in.
        displayScale = AndroidSurfaceHost.displayScale
        applyColorScheme(Self.systemColorScheme())
        // Dark mode switched while the app runs: the Activity handles the
        // configuration change itself (`uiMode` is in its configChanges) and
        // tells the host.
        AndroidSurfaceHost.onAppearanceChanged = { [weak self] in
            MainActor.assumeIsolated {
                self?.applyColorScheme(Self.systemColorScheme())
            }
        }
        // What covers the window: the soft keyboard from the bottom up, and
        // the system bars and the display cutout at its edges. The Activity
        // reports both from its window insets, from its first layout on, so
        // they can be there already.
        AndroidSurfaceHost.onKeyboardHeightChanged = { [weak self] duration in
            MainActor.assumeIsolated {
                self?.followKeyboard(duration: duration)
            }
        }
        AndroidSurfaceHost.onSafeAreaInsetsChanged = { [weak self] in
            MainActor.assumeIsolated {
                self?.followSafeArea()
            }
        }
        followSafeArea()
        followKeyboard(duration: 0)

        platformWindow.present()
    }
    #endif

    /// The engine was rebuilt against a new surface, so the canvas bound into
    /// the old one is gone with it.
    ///
    /// Only Android calls this: it is the one platform where the render surface
    /// can be destroyed and recreated under a window that outlives it — every
    /// background/resume cycle — so the node tree has to be rebound rather than
    /// rebuilt from scratch.
    public func on_surface_recreated() {
        MainActor.assumeIsolated {
            guard let engine = renderEngine else {
                nucleantLogError("NucleantUI: surface recreated with no engine — canvas not attached\n")
                return
            }
            // The `TextureView`s' textures belong to the old engine, which
            // is freed once this returns, and their sources write into them
            // from outside any pass — a video's next frame may already be
            // queued. Detached first, so those writes are refused: the next
            // pass hands each source a texture on the new engine.
            shaderSlots?.textures.detachAll()
            paintClearColor()
            attachCanvas(engine: engine, width: win_rect.z, height: win_rect.w)
        }
    }

    /// Build the window's canvas and bind it as the engine's slot for the
    /// tree, drawn by the window's renderer.
    @MainActor
    private func attachCanvas(engine: VulkanRenderEngine<Node>, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        // The registry first: its node manager makes every canvas, the
        // window's included, and holds what they share.
        let shaderSlots = ShaderSlotRegistry(engine: engine)
        shaderSlots.scale = displayScale
        shaderSlots.textures.window = self //as! HostingWindow<NucleantRenderNode>
        guard let canvas = shaderSlots.renderNodes.makeWindowCanvas(width: width, height: height) else { return }
        windowCanvas = canvas
        host.renderer = canvas.renderer
        // The views reach the registry through `ShaderHost`, which is still
        // `NucleantRenderNode`'s.
        host.shaderSlots = shaderSlots as? ShaderSlotRegistry<NucleantRenderNode>
        if host.shaderSlots == nil {
            nucleantLogError("NucleantUI: the views can't reach a \(Node.self) registry yet (ShaderHost is NucleantRenderNode's)\n")
        }
        self.shaderSlots = shaderSlots
        host.environment.displayScale = displayScale
        // The tree may already have been laid out against a size that arrived
        // before the canvas existed; force one pass through the new renderer.
        host.invalidate()
        markNeedsRedraw()
    }

    /// The canvas contents changed — rasterize it on the next engine pass.
    ///
    /// Set on the slot directly rather than left to Observation: the chain from
    /// `node.dirty` only fires on a *change*, so a second repaint while `dirty`
    /// was already `true` would raise no notification.
    @MainActor
    private func markNeedsRedraw() {
        windowCanvas?.markDirty()
    }

    // MARK: - NucleantWindow

    /// A frame already queued on the main dispatch queue and not yet run —
    /// a display-link tick that arrives meanwhile is dropped, not stacked.
    private var isFramePending = false

    /// The Δt the queued frame runs with: every tick's since the last frame
    /// ran, so a dropped tick's time is not lost with it.
    private var pendingDelta = 0.0

    /// Per display-link tick: queue one frame on the main dispatch queue.
    ///
    /// Not drawn here, in the display link's own callback. A frame blocks
    /// the main thread for most of a display period (the present waits for
    /// the next vsync), and a run loop whose display-link source is always
    /// ready and always slow never gets round to servicing the main
    /// dispatch queue — so `DispatchQueue.main.async`, `Task { @MainActor
    /// in … }` and `await MainActor.run` all sat unrun, sometimes for good,
    /// while a run-loop `Timer` fired fine. Seen as an `@Observable` model
    /// updated from a background analysis never redrawing. Queued through
    /// the main queue instead, the frame takes its FIFO turn with every
    /// other main-actor block, and the display-link callback is cheap
    /// enough that the loop always drains the queue before the next tick.
    public func onFrame(_ dt: Double) {
        #if os(Android) || os(Linux)
        // Both platforms tick from a loop of their own on the process main
        // thread — the Activity's Choreographer on Android, `X11Display.run()`
        // / `WaylandDisplay.run()` here — so the isolation holds, and there is
        // no run loop underneath either of them servicing the main *dispatch*
        // queue. A hop through `DispatchQueue.main.async` would queue frames
        // that nothing ever drains, which is a window that stays black.
        MainActor.assumeIsolated {
            pumpMainRunLoop()
            renderFrame(dt)
        }
        #elseif os(WASI)
        // The page's requestAnimationFrame, on its one thread. There is no
        // run loop to pump: work queued on the main queue is given turns of
        // its own by the page (Dispatch's MainQueue), so the frame just
        // draws.
        MainActor.assumeIsolated {
            renderFrame(dt)
        }
        #elseif os(Windows)
        // A turn of `Win32EventLoop.run()`, on the main thread. That loop
        // gives Foundation's run loop a pass every turn itself — the main
        // dispatch queue, `Task { @MainActor in … }`, `Timer`s — so the frame
        // just draws.
        MainActor.assumeIsolated {
            renderFrame(dt)
        }
        #else
        MainActor.assumeIsolated {
            pendingDelta += dt
            guard !isFramePending else { return }
            isFramePending = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isFramePending = false
                    let delta = self.pendingDelta
                    self.pendingDelta = 0
                    self.renderFrame(delta)
                }
            }
        }
        #endif
    }

    #if os(Android) || os(Linux)
    /// Give `RunLoop.main` one non-blocking turn, before the frame.
    ///
    /// The loop that calls `onFrame` is the platform's, not Foundation's, so
    /// on these two platforms nothing ever *ran* the main run loop: a
    /// `Timer` added to it never fired, and `DispatchQueue.main.async`,
    /// `Task { @MainActor in … }` and `await MainActor.run` were never
    /// drained either — the main-actor executor enqueues onto the main
    /// dispatch queue, which the run loop is what services. Anything an app
    /// scheduled rather than handled inline was simply dropped on the floor;
    /// seen as a once-a-second clock that never advanced.
    ///
    /// `before:` a date already past makes this a single pass that fires
    /// what is due and returns rather than blocking for more, which is the
    /// only shape that can be folded into someone else's loop. Before
    /// `renderFrame` so state a timer writes is picked up by *this* frame
    /// instead of waiting for the next one.
    ///
    /// Not needed on macOS or iOS: `NSApplication.run()` and
    /// `UIApplicationMain` are run loops, and pumping a run loop from inside
    /// its own callback is how you get re-entrant frames.
    private func pumpMainRunLoop() {
        _ = RunLoop.main.run(mode: .default, before: Date())
    }
    #endif

    /// Rebuild if anything invalidated, then let the engine composite.
    @MainActor
    private func renderFrame(_ dt: Double) {
        if host.update() {
            markNeedsRedraw()
        }
        #if os(Android) || os(iOS)
        syncSoftKeyboard()
        #endif
        // Out of sight, nothing reaches the GPU. The pass above still builds,
        // so the views hear what changed — their `onChange(of: scenePhase)`
        // among it — but places nothing (see `ViewHost.update`), and the
        // engine records, submits and presents nothing, and the shaders'
        // clocks wait with it. What changed meanwhile is on the first frame
        // back, which `enter` runs. Texture writes wait too (`ViewTexture`).
        guard scenePhase != .background else { return }
        // Shaders are animated by definition: advance their clocks and
        // re-arm them every frame. This is the one thing on screen that is
        // never idle, and it is opt-in — a tree with no `Shader` view in it
        // does nothing here.
        shaderSlots?.tick(dt, pointer: pointerLocation)
        // Nothing laid out and no node to render: the swapchain already
        // shows this frame, so there is nothing to record, submit or
        // present. Everything that changes what is on screen either runs a
        // pass (layout, animation, resize, appearance) or marks a node —
        // the window canvas, a painter copy, an animated shader, a texture
        // write.
        guard let renderEngine,
              host.didRunPass || renderEngine.nodes.contains(where: { $0.needsRender })
        else { return }
        renderEngine.drawFrame(dt)
    }

    #if os(Android)
    /// Ask for the soft keyboard the view with the keys needs — none, when
    /// it takes no text. Every frame, so focus moved by a tap, by Tab or by a
    /// focused view leaving the tree all count; the Activity reads it right
    /// after the frame.
    @MainActor
    private func syncSoftKeyboard() {
        let kind: AndroidSurfaceHost.TextInputKind
        switch host.focusedTextInput {
        case .none: kind = .none
        case .singleLine: kind = .singleLine
        case .multiLine: kind = .multiLine
        }
        if platformWindow?.textInputKind != kind {
            platformWindow?.textInputKind = kind
        }
    }

    /// The soft keyboard covers `AndroidSurfaceHost.keyboardHeight` of the
    /// window now, or will in `duration` seconds: the views are laid out
    /// above it, moving as it does. Android moves the keyboard on its own
    /// curve when an app follows it; one with no duration follows a
    /// gesture, a frame at a time.
    @MainActor
    private func followKeyboard(duration: Double) {
        host.setKeyboardHeight(
            AndroidSurfaceHost.keyboardHeight,
            animation: duration > 0 ? .timingCurve(0.2, 0, 0, 1, duration: duration) : nil
        )
    }

    /// The system bars and the display cutout keep
    /// `AndroidSurfaceHost.safeAreaInsets` clear: the views are laid out
    /// inside them, as the `.container` safe area. Left and right are the
    /// leading and trailing edges.
    @MainActor
    private func followSafeArea() {
        let insets = AndroidSurfaceHost.safeAreaInsets
        host.setSafeAreaInsets(EdgeInsets(
            top: insets.top, leading: insets.left,
            bottom: insets.bottom, trailing: insets.right
        ))
    }
    #elseif os(iOS)
    /// Put the on-screen keyboard up while the view with the keys takes
    /// text, and away when it takes none. Every frame, so focus moved by a
    /// tap, by Tab or by a focused view leaving the tree all count.
    @MainActor
    private func syncSoftKeyboard() {
        let kind: PlatformWindow<HostingWindow>.TextInputKind
        switch host.focusedTextInput {
        case .none: kind = .none
        case .singleLine: kind = .singleLine
        case .multiLine: kind = .multiLine
        }
        if platformWindow?.textInputKind != kind {
            platformWindow?.textInputKind = kind
        }
    }
    #endif

    /// Content resized to `w × h` **points**.
    public func on_size(w: Double, h: Double) {
        MainActor.assumeIsolated {
            #if os(macOS) || os(iOS)
            displayScale = Double(platformWindow?.metalLayer.contentsScale ?? 1)
            #elseif os(Linux)
            // The same re-read, from the backend's own scale: a window dragged
            // to a display with a different scale factor gets told through a
            // resize and nothing else.
            displayScale = platformWindow?.scale ?? 1
            #elseif os(WASI)
            // devicePixelRatio, which changes with the browser's zoom and
            // when the window moves to another display.
            displayScale = platformWindow?.scale ?? 1
            #elseif os(Windows)
            // The window's DPI over 96, which changes when it is moved to a
            // monitor with another scale — told through a resize.
            displayScale = platformWindow?.scale ?? 1
            #endif
            #if os(WASI) || os(Windows)
            // The page sizes the drawing buffer, which the swapchain follows,
            // from a CSS size that need not be whole pixels — 657.33 × 1.5 is
            // 986 there but truncates to 985 here, and a window canvas a pixel
            // off the swapchain's extent is never shown. So the page's numbers.
            // On Windows the points are pixels over the DPI scale, which can
            // come back a hair under the whole pixel count the same way.
            let pixelWidth = Int(platformWindow?.bufferWidth ?? UInt32(w * displayScale))
            let pixelHeight = Int(platformWindow?.bufferHeight ?? UInt32(h * displayScale))
            #else
            let pixelWidth = Int(w * displayScale)
            let pixelHeight = Int(h * displayScale)
            #endif
            win_rect.z = pixelWidth
            win_rect.w = pixelHeight

            host.renderer?.scale = displayScale
            shaderSlots?.scale = displayScale
            host.environment.displayScale = displayScale
            host.setSize(Size(width: w, height: h))

            // Not in the background, where nothing may reach the GPU — iOS
            // lays a scene out again for its snapshots there. The window
            // fits its canvas once it is back.
            if scenePhase != .background {
                fitCanvas()
            }
        }
    }

    /// Size the window canvas to `win_rect`. The canvas is sized in pixels
    /// and fills the window, so it follows the swapchain, keeping the node's
    /// identity — the slot and its z-order survive.
    @MainActor
    private func fitCanvas() {
        guard let engine = renderEngine else { return }
        let pixelWidth = win_rect.z, pixelHeight = win_rect.w
        if let canvas = windowCanvas, let renderNodes = shaderSlots?.renderNodes {
            if canvas.width != pixelWidth || canvas.height != pixelHeight {
                _ = renderNodes.resize(canvas, width: pixelWidth, height: pixelHeight)
                // The canvas is a new target at a new size — the tree has to
                // be repainted onto it, not just relaid out.
                host.invalidate()
            }
        } else {
            // The first size arrived before the canvas could be built (a
            // zero-sized window at bring-up) — build it now.
            attachCanvas(engine: engine, width: pixelWidth, height: pixelHeight)
        }
    }

    // MARK: - Phase

    /// The phase the platform last put the window in — `\.scenePhase` in
    /// its views. Every window starts out active.
    private(set) var scenePhase = ScenePhase.active

    public func on_phase_active() {
        enter(.active)
    }

    public func on_phase_inactive() {
        enter(.inactive)
    }

    public func on_phase_background() {
        enter(.background)
    }

    /// Put `phase` into the root environment, so the views that read
    /// `\.scenePhase` are built again with it, and run a frame for them now.
    /// Not on the next tick: a window out of sight gets none — macOS stops
    /// its display link while it is minimized or the app is hidden, iOS in
    /// the background — so an `onChange(of: scenePhase)` would wait until
    /// the window came back.
    private func enter(_ phase: ScenePhase) {
        let changed = MainActor.assumeIsolated {
            guard phase != scenePhase else { return false }
            let wasInBackground = scenePhase == .background
            scenePhase = phase
            host.environment.scenePhase = phase
            host.invalidate()
            // A resize while out of sight left the canvas at the old size.
            if wasInBackground, win_rect.z > 0, win_rect.w > 0 {
                fitCanvas()
            }
            return true
        }
        if changed {
            onFrame(0)
        }
    }

    // MARK: - Input

    /// AppKit reports mouse locations from the window's *bottom* left; the view
    /// system works top-down, so the y axis is flipped once, here.
    private func viewPoint(x: Double, y: Double) -> Point {
        #if os(macOS)
        return Point(x: x, y: contentHeightInPoints - y)
        #elseif os(Android)
        // MotionEvent reports pixels; the view tree is laid out in points.
        // Apple hands UIKit/AppKit coordinates over already in points, which
        // is why only this platform divides.
        let scale = displayScale > 0 ? displayScale : 1
        return Point(x: x / scale, y: y / scale)
        #else
        return Point(x: x, y: y)
        #endif
    }

    private var contentHeightInPoints: Double {
        Double(win_rect.w) / (displayScale > 0 ? displayScale : 1)
    }

    /// The input delegate, for a press at `point` that no view takes there
    /// — nothing to ask when there is no delegate.
    @MainActor
    private func delegate(at point: Point) -> WindowInputDelegate? {
        guard let delegate = input.delegate, delegate.windowWantsInput(at: point), !host.takesPress(at: point) else {
            return nil
        }
        return delegate
    }

    /// The input delegate, for a hover or a wheel at `point` that no view
    /// takes there.
    @MainActor
    private func delegate(pointingAt point: Point) -> WindowInputDelegate? {
        guard let delegate = input.delegate, delegate.windowWantsInput(at: point), !host.takesPointer(at: point) else {
            return nil
        }
        return delegate
    }

    public func on_mouse_down(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            let modifiers = currentModifiers
            if delegate(at: point)?.windowMouseDown(at: point, modifiers: modifiers) == true {
                delegateHasMouse = true
                host.clearFocus()
                return
            }
            host.pointerDown(at: point, modifiers: modifiers)
        }
    }

    public func on_mouse_up(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegateHasMouse {
                delegateHasMouse = false
                _ = input.delegate?.windowMouseUp(at: point)
                return
            }
            host.pointerUp(at: point)
        }
    }

    public func on_mouse_dragged(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegateHasMouse {
                _ = input.delegate?.windowMouseDragged(to: point)
                return
            }
            host.pointerMoved(to: point)
        }
    }

    public func on_mouse_moved(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            pointerLocation = point
            if delegate(pointingAt: point)?.windowMouseMoved(to: point) == true { return }
            host.pointerMoved(to: point)
        }
    }

    public func on_right_mouse_down(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegate(at: point)?.windowRightMouseDown(at: point) == true {
                delegateHasRightMouse = true
                host.clearFocus()
                return
            }
            host.secondaryClick(at: point)
        }
    }

    public func on_right_mouse_up(x: Double, y: Double) {
        MainActor.assumeIsolated {
            guard delegateHasRightMouse else { return }
            delegateHasRightMouse = false
            _ = input.delegate?.windowRightMouseUp(at: viewPoint(x: x, y: y))
        }
    }

    public func on_scroll(dx: Double, dy: Double) {
        MainActor.assumeIsolated {
            if delegate(pointingAt: pointerLocation)?.windowScroll(dx: dx, dy: dy, at: pointerLocation) == true { return }
            host.scroll(dx: dx, dy: dy)
        }
    }

    /// Keys go to the view that has them; the delegate has them only while
    /// none does.
    public func on_key_down(keyCode: UInt16, characters: String?) {
        MainActor.assumeIsolated {
            let modifiers = currentModifiers
            if let delegate = input.delegate, !host.hasFocusedView,
               delegate.windowKeyDown(keyCode: keyCode, characters: characters, modifiers: modifiers) {
                return
            }
            host.keyDown(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
    }

    public func on_key_up(keyCode: UInt16, characters: String?) {
        MainActor.assumeIsolated {
            let modifiers = currentModifiers
            if let delegate = input.delegate, !host.hasFocusedView,
               delegate.windowKeyUp(keyCode: keyCode, characters: characters, modifiers: modifiers) {
                return
            }
            host.keyUp(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
    }

    /// The modifier keys of the key or mouse event being delivered. The
    /// platform's callbacks carry no modifiers, but they run while AppKit is
    /// dispatching that event — so it is `NSApp.currentEvent`, when that is
    /// a key event or a press, and otherwise the keyboard's live state.
    @MainActor
    private var currentModifiers: EventModifiers {
        #if os(macOS)
        let current = NSApp.currentEvent
        let flags = current.map { [.keyDown, .keyUp, .leftMouseDown].contains($0.type) } == true
            ? current!.modifierFlags
            : NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
        #elseif os(Windows)
        // The keyboard as of the message being handled: GetKeyState follows
        // the key messages the thread has read. Ctrl is the command key here,
        // as Platform_Windows reads menu shortcuts, and Alt is Option — except
        // together, which is AltGr typing a character ("@" on a German
        // keyboard), and so neither.
        var modifiers: EventModifiers = []
        let control = GetKeyState(VK_CONTROL) < 0, alt = GetKeyState(VK_MENU) < 0
        if GetKeyState(VK_SHIFT) < 0 { modifiers.insert(.shift) }
        if control && !alt { modifiers.insert(.command) }
        if alt && !control { modifiers.insert(.option) }
        return modifiers
        #elseif os(iOS)
        // The modifiers of the key press being delivered, which the window
        // keeps from each press's event; none for the on-screen keyboard's.
        let flags = platformWindow?.keyModifierFlags ?? []
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
        #else
        return []
        #endif
    }

    public func on_magnify(phase: TrackpadGesturePhase, delta: Double, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegate(pointingAt: point)?.windowMagnify(phase: phase, delta: delta, at: point) == true { return }
            host.magnify(phase: phase, delta: delta, at: point)
        }
    }

    public func on_rotate(phase: TrackpadGesturePhase, delta: Double, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegate(pointingAt: point)?.windowRotate(phase: phase, delta: delta, at: point) == true { return }
            host.rotate(phase: phase, delta: delta, at: point)
        }
    }

    public func on_touch_down(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if delegate(at: point)?.windowTouchDown(id: id, at: point) == true {
                delegateTouches.insert(id)
                host.clearFocus()
                return
            }
            host.pointerDown(id: id, at: point)
        }
    }

    public func on_touch_moved(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if !delegateTouches.isEmpty, delegateTouches.contains(id) {
                _ = input.delegate?.windowTouchMoved(id: id, to: point)
                return
            }
            host.pointerMoved(id: id, to: point)
        }
    }

    public func on_touch_up(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if !delegateTouches.isEmpty, delegateTouches.remove(id) != nil {
                _ = input.delegate?.windowTouchUp(id: id, at: point)
                return
            }
            host.pointerUp(id: id, at: point)
        }
    }

    public func on_touch_cancelled(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if !delegateTouches.isEmpty, delegateTouches.remove(id) != nil {
                _ = input.delegate?.windowTouchCancelled(id: id, at: point)
                return
            }
            host.pointerCancelled(id: id, at: point)
        }
    }
}

public enum HostingWindowError: Error {
    case unsupportedPlatform
}

#if os(macOS)
// `PlatformWindow` routes AppKit events to its `win_delegate` through
// `WindowBaseDelegate`; the mapping onto the `on_*` methods above is the
// default implementation on `NucleantWindow where Self: WindowBaseDelegate`.
extension HostingWindow: WindowBaseDelegate {}
#endif

#if os(iOS)
extension HostingWindow: WindowTouchDelegate {
    /// The on-screen keyboard put away from the keyboard: the field loses
    /// the keys with it, as in SwiftUI.
    public func keyboardDismissed() {
        MainActor.assumeIsolated {
            if host.focusedTextInput != .none { host.clearFocus() }
        }
    }

    /// The on-screen keyboard is about to cover `height` of the window: the
    /// views are laid out above it, moving as the keyboard does.
    public func keyboardHeightChanged(_ height: CGFloat, duration: TimeInterval, curve: UIView.AnimationCurve) {
        MainActor.assumeIsolated {
            host.setKeyboardHeight(Double(height), animation: Self.keyboardAnimation(curve: curve, duration: duration))
        }
    }

    /// The window's edges keep `insets` clear: the views are laid out
    /// inside them, as the `.container` safe area. Left and right are the
    /// leading and trailing edges.
    public func safeAreaInsetsChanged(_ insets: UIEdgeInsets) {
        MainActor.assumeIsolated {
            host.setSafeAreaInsets(EdgeInsets(
                top: Double(insets.top), leading: Double(insets.left),
                bottom: Double(insets.bottom), trailing: Double(insets.right)
            ))
        }
    }

    /// UIKit's animation curve as SwiftUI turns it into an animation. The
    /// keyboard's own, 7, is a spring that takes no duration. A timed curve
    /// over no time is no animation: the views jump.
    private static func keyboardAnimation(curve: UIView.AnimationCurve, duration: TimeInterval) -> Animation? {
        if curve.rawValue == 7 {
            return .interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)
        }
        guard duration > 0 else { return nil }
        switch curve.rawValue {
        case 0, 6: return .easeInOut(duration: duration)
        case 1: return .easeIn(duration: duration)
        case 2: return .easeOut(duration: duration)
        case 3: return .linear(duration: duration)
        case 4: return .timingCurve(0.66, 0, 0.33, 1, duration: duration)
        // Core Animation's default timing function.
        case 5: return .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
        default: return nil
        }
    }
}
#endif

#if os(Linux)
// Linux is the one platform where pointer, keyboard and touch are all live at
// once — a `wl_seat` can advertise all three — so `WaylandWindowDelegate` is
// the union of the two Apple protocols above. Its default implementations
// (Platform_Linux) forward to the same `on_*` methods.
extension HostingWindow: WaylandWindowDelegate {}
#endif

#if os(Windows)
// Like Wayland's, the union of the Apple protocols: a Windows laptop has a
// mouse, a keyboard and a touch screen at once. Its default implementations
// (Platform_Windows) forward to the same `on_*` methods.
extension HostingWindow: Win32WindowDelegate {}
#endif

#if os(WASI)
// A page reports mouse, keyboard and touch at once, as pointer events, so
// like Wayland's this is the union of the Apple protocols; its default
// implementations (Platform_Wasm) forward to the same `on_*` methods.
extension HostingWindow: BrowserWindowDelegate {
    // Which of them the page has can't be known up front — a laptop with a
    // touch screen has both — so the press decides: a finger scrolls what it
    // drags and holds for a context menu, as on iOS; a mouse scrolls with
    // its wheel and has a right button.

    public func touchDown(id: Int, location: SIMD2<Double>) {
        MainActor.assumeIsolated {
            host.scrollsOnDrag = true
            host.opensContextMenuOnLongPress = true
        }
        on_touch_down(id: id, x: location.x, y: location.y)
    }

    public func mouseDown(location: SIMD2<Double>) {
        MainActor.assumeIsolated {
            host.scrollsOnDrag = false
            host.opensContextMenuOnLongPress = false
        }
        on_mouse_down(x: location.x, y: location.y)
    }
}
#endif
