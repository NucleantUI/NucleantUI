//
//  Window.swift
//  NucleantUI
//

import NucleantVulkan
import NucleantWindow

/// A scene that presents its content in a single, unique window.
///
/// Next to the app's main `WindowGroup`, a window for something on the
/// side, which opens from the Window menu, where it is listed by its title,
/// or from `openWindow(id:)`. Asked for while it is open, it comes to the
/// front instead of opening again:
///
/// ```swift
/// @main
/// struct Mail: NucleantApp {
///     var body: some Scene {
///         WindowGroup("Mail") { MailViewer() }
///         Window("Connection Doctor", id: "connection-doctor") {
///             ConnectionDoctor()
///         }
///     }
/// }
/// ```
///
/// Declared first, it is the window the app opens at launch. Closed and
/// opened again, its content starts over with fresh state.
public struct Window<Content: View>: Scene {
    let title: String
    let id: String
    let content: Content

    /// A window titled `title` — in its title bar and its Window menu
    /// item — that `openWindow(id:)` opens. Ids are unique among the app's
    /// `WindowGroup`s and `Window`s.
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) {
        self.title = String(title)
        self.id = id
        self.content = content()
    }

    public func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        [HostingWindow(title: title, root: content)]
    }

    public func _windowScenes<Node: NucleantContainerNode>(into scenes: inout [_WindowScene<Node>]) {
        scenes.append(_WindowScene(id: id, title: title, kind: .unique) {
            self._makeWindows()
        })
    }

    public func _lowerCommands(into menuBar: MenuBar) {}
}
