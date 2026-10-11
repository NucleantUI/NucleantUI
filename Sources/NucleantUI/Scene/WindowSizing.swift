//
//  WindowSizing.swift
//  NucleantUI
//
//  How big a scene's windows are: `defaultSize`, `windowResizability` and
//  `windowIdealSize`, the same scene modifiers as SwiftUI's. A window's size
//  is not an input of `WindowGroup`; where a platform lets the window be
//  resized — a desktop window, a browser page — these say where it starts
//  and how far it may go, and the content's own frame supplies the limits.
//

import NucleantWindow

/// The strategy a scene's windows use for their minimum and maximum size.
///
/// The limits come from the window's content — its size when offered
/// nothing, and when offered all the space there is — so they follow the
/// `.frame` constraints on the root view:
///
/// ```swift
/// WindowGroup("Calculator") {
///     CalculatorView()
///         .frame(minWidth: 300, maxWidth: 420, minHeight: 480, maxHeight: 640)
/// }
/// .windowResizability(.contentSize)
/// ```
///
/// A window that can't be resized at all is `.contentSize` over content
/// whose minimum and maximum are the same — a fixed `.frame(width:height:)`.
public struct WindowResizability: Sendable, Hashable {
    enum Role: Hashable {
        case automatic
        case contentSize
        case contentMinSize
    }

    let role: Role

    /// The strategy that suits the scene. For a `WindowGroup`, that is
    /// ``contentMinSize``.
    public static var automatic: WindowResizability { WindowResizability(role: .automatic) }

    /// A minimum size that matches the content's minimum size, and a maximum
    /// size that matches its maximum size.
    public static var contentSize: WindowResizability { WindowResizability(role: .contentSize) }

    /// A minimum size that matches the content's minimum size, and no
    /// maximum size.
    public static var contentMinSize: WindowResizability { WindowResizability(role: .contentMinSize) }
}

/// The size a window takes when it is zoomed — the macOS window's green
/// button, or double-clicking its title bar.
public struct WindowIdealSize: Sendable, Hashable {
    enum Role: Hashable {
        case automatic
        case fitToContent
        case maximum
    }

    let role: Role

    /// The system's behavior: as large as the screen allows, within the
    /// window's maximum size.
    public static let automatic = WindowIdealSize(role: .automatic)

    /// The ideal size of the window's content — its size when offered no
    /// particular size, which `.frame(idealWidth:idealHeight:)` sets.
    public static let fitToContent = WindowIdealSize(role: .fitToContent)

    /// The maximum size of the window's content.
    public static let maximum = WindowIdealSize(role: .maximum)
}

extension Scene {
    /// Sets a default size for the windows this scene creates.
    ///
    /// The size a window opens at; people can resize it after that. A size
    /// outside the window's resizability is clamped into it. Where the
    /// platform decides the window's size itself it has no effect: on iOS
    /// and Android the window is the screen, and in a browser it is the page.
    public func defaultSize(_ size: Size) -> some Scene {
        WindowSizingScene(base: self) { sizing in
            if sizing.defaultSize == nil { sizing.defaultSize = size }
        }
    }

    /// Sets a default width and height for the windows this scene creates.
    /// See ``defaultSize(_:)``.
    public func defaultSize(width: Double, height: Double) -> some Scene {
        defaultSize(Size(width: width, height: height))
    }

    /// Sets the kind of resizability to use for the windows this scene
    /// creates. Without it a window uses ``WindowResizability/automatic``.
    public func windowResizability(_ resizability: WindowResizability) -> some Scene {
        WindowSizingScene(base: self) { sizing in
            if sizing.resizability == nil { sizing.resizability = resizability }
        }
    }

    /// Specifies how the windows this scene creates size themselves when
    /// zooming. Without it a window uses ``WindowIdealSize/automatic``.
    public func windowIdealSize(_ idealSize: WindowIdealSize) -> some Scene {
        WindowSizingScene(base: self) { sizing in
            if sizing.idealSize == nil { sizing.idealSize = idealSize }
        }
    }
}

/// What a scene's sizing modifiers settled for one window. Each modifier
/// fills only what no modifier closer to the scene already has, so the
/// nearest one wins.
struct WindowSizing {
    var defaultSize: Size?
    var resizability: WindowResizability?
    var idealSize: WindowIdealSize?

    /// The size a window opens at when no `defaultSize` says otherwise.
    static let fallbackSize = Size(width: 900, height: 600)

    /// Which of the content's sizes the window's limits are made of.
    var measurements: ContentSizeLimits.Measurements {
        var measurements: ContentSizeLimits.Measurements = []
        switch resizability?.role ?? .automatic {
        case .automatic, .contentMinSize:
            measurements.insert(.minimum)
        case .contentSize:
            measurements.formUnion([.minimum, .maximum])
        }
        switch idealSize?.role ?? .automatic {
        case .automatic:
            break
        case .fitToContent:
            measurements.insert(.ideal)
        case .maximum:
            measurements.insert(.maximum)
        }
        return measurements
    }

    /// Where `size` lands within `limits`.
    static func clamp(_ size: Size, to limits: ContentSizeLimits) -> Size {
        var size = size
        if let maximum = limits.maximum {
            size.width = min(size.width, maximum.width)
            size.height = min(size.height, maximum.height)
        }
        if let minimum = limits.minimum {
            size.width = max(size.width, minimum.width)
            size.height = max(size.height, minimum.height)
        }
        return size
    }

    /// The content size zooming goes to, or `nil` for the system's own.
    func zoomSize(for limits: ContentSizeLimits) -> Size? {
        switch idealSize?.role ?? .automatic {
        case .automatic:
            return nil
        case .fitToContent:
            return limits.ideal.map { Self.clamp($0, to: limits) }
        case .maximum:
            guard let maximum = limits.maximum, maximum.width.isFinite, maximum.height.isFinite else { return nil }
            return maximum
        }
    }
}

/// The content's own sizes, measured from the root view, that a window's
/// limits are made of. `nil` for one nobody asked to measure.
public struct ContentSizeLimits: Hashable, Sendable {
    /// Its size offered zero: as small as it goes.
    public var minimum: Size?
    /// Its size offered infinity: as large as it goes. Infinite on an axis
    /// where it takes whatever it is offered.
    public var maximum: Size?
    /// Its size offered nothing in particular.
    public var ideal: Size?

    public init(minimum: Size? = nil, maximum: Size? = nil, ideal: Size? = nil) {
        self.minimum = minimum
        self.maximum = maximum
        self.ideal = ideal
    }

    /// True when the window can't be resized: no room between the minimum
    /// and the maximum on either axis.
    public var isFixed: Bool {
        guard let minimum, let maximum else { return false }
        return maximum.width <= minimum.width && maximum.height <= minimum.height
    }

    struct Measurements: OptionSet {
        let rawValue: Int
        static let minimum = Measurements(rawValue: 1 << 0)
        static let maximum = Measurements(rawValue: 1 << 1)
        static let ideal = Measurements(rawValue: 1 << 2)
    }
}

/// A sizing modifier: the scene it wraps, with one more say in its windows'
/// sizing.
struct WindowSizingScene<Base: Scene>: Scene {
    let base: Base
    let apply: (inout WindowSizing) -> Void

    var body: Never { fatalError() }

    func _makeWindows() -> [HostingWindow] {
        let windows = base._makeWindows()
        for window in windows {
            apply(&window.sizing)
        }
        return windows
    }

    func _lowerCommands(into menuBar: MenuBar) {
        base._lowerCommands(into: menuBar)
    }
}
