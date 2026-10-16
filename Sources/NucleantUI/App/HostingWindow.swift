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

public final class HostingWindow<Node: NucleantContainerNode>: NucleantWindow, @unchecked Sendable {

    //public typealias Node = NucleantRenderNode

    public var renderEngine: VulkanRenderEngine<Node>?

    /// (x, y, width, height) in *pixels*, like every other Nucleant window.
    public var win_rect: SIMD4<Int>

    let title: String

    /// The view tree. Isolated to the main actor; every access below goes
    /// through `assumeIsolated`.
    let host: ViewHost

    /// The window's input as its views reach it (`\.windowInput`): its
    /// delegate hears each event before `host` does.
    let input: WindowInput

    #if os(macOS) || os(iOS) || os(Android) || os(Linux) || os(WASI)
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
            #else
            throw HostingWindowError.unsupportedPlatform
            #endif
        }
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
        #elseif os(Linux)
        // The desktop's own setting, through the XDG portal — see
        // DesktopAppearance. A desktop with no preference gets light, the same
        // answer as a platform with nothing to ask.
        return DesktopAppearance.colorScheme() == .dark ? .dark : .light
        #elseif os(WASI)
        // The page's `prefers-color-scheme` — see BrowserAppearance.
        return BrowserAppearance.colorScheme() == .dark ? .dark : .light
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
        let background = Color.background.resolved(for: scheme)
        renderEngine?.clearColor = (
            Float(background.red), Float(background.green), Float(background.blue), 1
        )
        host.invalidate()
        markNeedsRedraw()
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

        // 2. The Vulkan engine renders into that layer.
        let engine = try VulkanRenderEngine<Node>(metalLayer: platformWindow.metalLayer)
        self.renderEngine = engine
        self.platformWindow = platformWindow
        platformWindow.win_delegate = self

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
        // window would be.
        platformWindow.center()
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
        host.opensContextMenuOnLongPress = true
        // Points-to-pixels, from the display. Android reports it as
        // `DisplayMetrics.density` and only Java can read it, so the Activity
        // hands it over before the app starts — see AndroidSurfaceHost. The
        // surface size arrives in pixels, so this is what turns it into the
        // points the layout works in.
        displayScale = AndroidSurfaceHost.displayScale
        applyColorScheme(Self.systemColorScheme())

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
            #endif
            #if os(WASI)
            // The page sizes the drawing buffer, which the swapchain follows,
            // from a CSS size that need not be whole pixels — 657.33 × 1.5 is
            // 986 there but truncates to 985 here, and a window canvas a pixel
            // off the swapchain's extent is never shown. So the page's numbers.
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

            // The canvas is sized in pixels and fills the window, so it follows
            // the swapchain, keeping the node's identity — the slot and its
            // z-order survive.
            if let engine = renderEngine {
                if let canvas = windowCanvas, let renderNodes = shaderSlots?.renderNodes {
                    if canvas.width != pixelWidth || canvas.height != pixelHeight {
                        _ = renderNodes.resize(canvas, width: pixelWidth, height: pixelHeight)
                        // The canvas is a new target at a new size — the tree
                        // has to be repainted onto it, not just relaid out.
                        host.invalidate()
                    }
                } else {
                    // The first size arrived before the canvas could be built
                    // (a zero-sized window at bring-up) — build it now.
                    attachCanvas(engine: engine, width: pixelWidth, height: pixelHeight)
                }
            }
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

    public func on_mouse_down(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            let modifiers = Self.currentModifiers
            if input.delegate?.windowMouseDown(at: point, modifiers: modifiers) == true { return }
            host.pointerDown(at: point, modifiers: modifiers)
        }
    }

    public func on_mouse_up(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowMouseUp(at: point) == true { return }
            host.pointerUp(at: point)
        }
    }

    public func on_mouse_dragged(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowMouseDragged(to: point) == true { return }
            host.pointerMoved(to: point)
        }
    }

    public func on_mouse_moved(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            pointerLocation = point
            if input.delegate?.windowMouseMoved(to: point) == true { return }
            host.pointerMoved(to: point)
        }
    }

    public func on_right_mouse_down(x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowRightMouseDown(at: point) == true { return }
            host.secondaryClick(at: point)
        }
    }

    public func on_right_mouse_up(x: Double, y: Double) {
        MainActor.assumeIsolated {
            _ = input.delegate?.windowRightMouseUp(at: viewPoint(x: x, y: y))
        }
    }

    public func on_scroll(dx: Double, dy: Double) {
        MainActor.assumeIsolated {
            if input.delegate?.windowScroll(dx: dx, dy: dy, at: pointerLocation) == true { return }
            host.scroll(dx: dx, dy: dy)
        }
    }

    public func on_key_down(keyCode: UInt16, characters: String?) {
        MainActor.assumeIsolated {
            let modifiers = Self.currentModifiers
            if input.delegate?.windowKeyDown(keyCode: keyCode, characters: characters, modifiers: modifiers) == true { return }
            host.keyDown(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
    }

    public func on_key_up(keyCode: UInt16, characters: String?) {
        MainActor.assumeIsolated {
            let modifiers = Self.currentModifiers
            if input.delegate?.windowKeyUp(keyCode: keyCode, characters: characters, modifiers: modifiers) == true { return }
            host.keyUp(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
    }

    /// The modifier keys of the key or mouse event being delivered. The
    /// platform's callbacks carry no modifiers, but they run while AppKit is
    /// dispatching that event — so it is `NSApp.currentEvent`, when that is
    /// a key event or a press, and otherwise the keyboard's live state.
    private static var currentModifiers: EventModifiers {
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
        #else
        return []
        #endif
    }

    public func on_magnify(phase: TrackpadGesturePhase, delta: Double, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowMagnify(phase: phase, delta: delta, at: point) == true { return }
            host.magnify(phase: phase, delta: delta, at: point)
        }
    }

    public func on_rotate(phase: TrackpadGesturePhase, delta: Double, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowRotate(phase: phase, delta: delta, at: point) == true { return }
            host.rotate(phase: phase, delta: delta, at: point)
        }
    }

    public func on_touch_down(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowTouchDown(id: id, at: point) == true { return }
            host.pointerDown(id: id, at: point)
        }
    }

    public func on_touch_moved(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowTouchMoved(id: id, to: point) == true { return }
            host.pointerMoved(id: id, to: point)
        }
    }

    public func on_touch_up(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowTouchUp(id: id, at: point) == true { return }
            host.pointerUp(id: id, at: point)
        }
    }

    public func on_touch_cancelled(id: Int, x: Double, y: Double) {
        MainActor.assumeIsolated {
            let point = viewPoint(x: x, y: y)
            if input.delegate?.windowTouchCancelled(id: id, at: point) == true { return }
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
extension HostingWindow: WindowTouchDelegate {}
#endif

#if os(Linux)
// Linux is the one platform where pointer, keyboard and touch are all live at
// once — a `wl_seat` can advertise all three — so `WaylandWindowDelegate` is
// the union of the two Apple protocols above. Its default implementations
// (Platform_Linux) forward to the same `on_*` methods.
extension HostingWindow: WaylandWindowDelegate {}
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
