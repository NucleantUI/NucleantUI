//
//  Scene.swift
//  NucleantUI
//

import NucleantVulkan
import NucleantWindow

/// A part of an app's user interface with a life cycle — currently, a window.
///
/// The same shape as `View`: a scene is either a composition of other
/// scenes, declared through `body`, or a primitive one (`WindowGroup`,
/// `Window`, `TupleScene`, a `.commands` scene) that has `Body == Never` and
/// answers the hooks below itself. A composite reduces to primitives through
/// the hooks' defaults, which recurse into `body`.
@MainActor @preconcurrency
public protocol Scene {
    /// The type of scene representing the body of this scene.
    associatedtype Body: Scene

    /// The content and behavior of the scene. Primitive scenes declare
    /// `Body == Never` and are never asked for it.
    @SceneBuilder @MainActor @preconcurrency var body: Body { get }

    /// Every window this scene makes, made at once.
    func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>]

    /// The scenes the app shows — each `WindowGroup`, `Window` and
    /// `SystemTray` — in the order they are declared. When the first is a
    /// window scene the app opens its window at launch, and the others'
    /// when asked for them by id.
    func _scenes<Node: NucleantContainerNode>(into scenes: inout _AppScenes<Node>)

    /// The scene's `.commands`, added to the app's menu bar.
    func _lowerCommands(into menuBar: MenuBar)
}

extension Scene {
    public func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        body._makeWindows()
    }

    public func _scenes<Node: NucleantContainerNode>(into scenes: inout _AppScenes<Node>) {
        if Body.self == Never.self {
            // A primitive scene that only makes its windows: one scene,
            // opening them all, with no id to be asked for by.
            scenes.append(_WindowScene(id: nil, title: "", kind: .launchOnly) {
                self._makeWindows()
            })
        } else {
            body._scenes(into: &scenes)
        }
    }

    public func _lowerCommands(into menuBar: MenuBar) {
        body._lowerCommands(into: menuBar)
    }
}

extension Scene where Body == Never {
    public var body: Never {
        preconditionFailure("body should not be called on the primitive scene \(Self.self).")
    }
}

/// The scenes an app shows, as its body declares them: its window scenes
/// and its system tray items, each in order, and which kind came first.
@MainActor
public struct _AppScenes<Node: NucleantContainerNode> {
    public private(set) var windows: [_WindowScene<Node>] = []
    public private(set) var systemTrays: [_SystemTrayScene<Node>] = []

    /// Whether the first scene declared is a window scene, the one whose
    /// window the app opens at launch. A `SystemTray` first opens none.
    public private(set) var opensWindowAtLaunch = false

    /// What `.dockIcon(_:)` said, the first one in the body; `nil` for none.
    public private(set) var dockIcon: Visibility?

    private var isEmpty = true

    public init() {}

    public mutating func append(_ window: _WindowScene<Node>) {
        if isEmpty { opensWindowAtLaunch = true }
        isEmpty = false
        windows.append(window)
    }

    public mutating func append(_ tray: _SystemTrayScene<Node>) {
        isEmpty = false
        systemTrays.append(tray)
    }

    /// `.dockIcon(_:)` over these scenes, unless one inside them said it.
    public mutating func sayDockIcon(_ visibility: Visibility) {
        if dockIcon == nil { dockIcon = visibility }
    }

    /// `other`'s scenes, after these.
    public mutating func append(contentsOf other: _AppScenes<Node>) {
        if isEmpty { opensWindowAtLaunch = other.opensWindowAtLaunch }
        if dockIcon == nil { dockIcon = other.dockIcon }
        isEmpty = isEmpty && other.isEmpty
        windows += other.windows
        systemTrays += other.systemTrays
    }

    /// Each window scene replaced by what `transform` makes of it.
    public mutating func mapWindows(_ transform: (_WindowScene<Node>) -> _WindowScene<Node>) {
        windows = windows.map(transform)
    }

    /// Each tray replaced by what `transform` makes of it.
    public mutating func mapSystemTrays(_ transform: (_SystemTrayScene<Node>) -> _SystemTrayScene<Node>) {
        systemTrays = systemTrays.map(transform)
    }
}

/// One scene that opens windows, as the app keeps it: what it is asked for
/// by, what its menu items call it, and how to make its window.
@MainActor
public struct _WindowScene<Node: NucleantContainerNode> {
    /// What `openWindow(id:)` asks for it by; `nil` when it has none.
    public let id: String?

    /// Its title, for the menu items that open it.
    public let title: String

    /// How it opens.
    public let kind: Kind

    public enum Kind: Sendable {
        /// Another window each time — a `WindowGroup`, with a New Window
        /// item in the File menu.
        case group
        /// One window at most, brought to the front when asked for again —
        /// a `Window`, listed in the Window menu.
        case unique
        /// Its windows once, at launch when it is the app's first scene,
        /// and never from a menu: a scene that only makes its windows
        /// (`_makeWindows`).
        case launchOnly
    }

    /// The windows one opening makes, sized as the scene's modifiers say.
    public let makeWindows: @MainActor () -> [HostingWindow<Node>]

    public init(
        id: String?,
        title: String,
        kind: Kind,
        makeWindows: @escaping @MainActor () -> [HostingWindow<Node>]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.makeWindows = makeWindows
    }
}

// MARK: - Never as a Scene

extension Never: Scene {}
