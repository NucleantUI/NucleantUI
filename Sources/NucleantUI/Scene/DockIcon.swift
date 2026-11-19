//
//  DockIcon.swift
//  NucleantUI
//
//  `.dockIcon(_:)`: whether the app's icon is in the Dock, with its menus in
//  the menu bar, or the app is only in the system tray. An app with a
//  `SystemTray` has the icon while one of its windows is open, and is in the
//  tray alone once they are closed; this says otherwise.
//

import NucleantVulkan
import NucleantWindow

extension Scene {
    /// Whether the app's icon is in the Dock — and its menus in the menu
    /// bar — or the app is only in the system tray.
    ///
    /// ```swift
    /// SystemTray("Timer", systemImage: "timer") { … }
    ///     .dockIcon(.hidden)
    /// ```
    ///
    /// `.automatic`, without it, is the icon always for an app with no
    /// `SystemTray`, and, for one with a `SystemTray`, the icon while one of
    /// its windows is open — not the tray's own — and none once they are
    /// all closed. `.visible` keeps the icon whatever is open, `.hidden`
    /// keeps the app in the tray even with windows open. For the app,
    /// wherever in its body it is written; the first one in the body wins.
    /// On macOS; elsewhere it does nothing.
    public func dockIcon(_ visibility: Visibility) -> some Scene {
        DockIconScene(base: self, visibility: visibility)
    }
}

/// `.dockIcon(_:)`: the scene it wraps, and what it says of the Dock.
struct DockIconScene<Base: Scene>: Scene {
    let base: Base
    let visibility: Visibility

    var body: Never { fatalError() }

    func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        base._makeWindows()
    }

    func _scenes<Node: NucleantContainerNode>(into scenes: inout _AppScenes<Node>) {
        var inner = _AppScenes<Node>()
        base._scenes(into: &inner)
        inner.sayDockIcon(visibility)
        scenes.append(contentsOf: inner)
    }

    func _lowerCommands(into menuBar: MenuBar) {
        base._lowerCommands(into: menuBar)
    }
}

extension _AppScenes {
    /// Whether the app's icon belongs in the Dock now, with a window of its
    /// own open or not.
    func showsDockIcon(hasOpenWindow: Bool) -> Bool {
        switch dockIcon ?? .automatic {
        case .visible: return true
        case .hidden: return false
        default: return systemTrays.isEmpty || hasOpenWindow
        }
    }
}
