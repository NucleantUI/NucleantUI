//
//  WindowGroup.swift
//  NucleantUI
//

import NucleantVulkan
import NucleantWindow

/// A scene that presents a group of identically structured windows.
///
/// The content is a template: each window the group opens builds it anew,
/// with state of its own. The app opens one window at launch when the group
/// is the first scene it declares. Another opens from the menu bar's File ›
/// New Window, and, for a group with an id, from `openWindow(id:)`:
///
/// ```swift
/// @main
/// struct Mail: NucleantApp {
///     var body: some Scene {
///         WindowGroup("Mail") { MailViewer() }
///         WindowGroup("Message", id: "message") { MessageComposer() }
///     }
/// }
///
/// @View
/// struct ComposeButton {
///     @Environment(\.openWindow) private var openWindow
///
///     var body: some View {
///         Button("New Message") { openWindow(id: "message") }
///     }
/// }
/// ```
///
/// The window's size isn't an input: `defaultSize(width:height:)` says what
/// it opens at, `windowResizability(_:)` how its content limits it, and
/// `windowIdealSize(_:)` what zooming does. Without them a desktop window
/// opens at 900 × 600 and can't be made smaller than its content; in a
/// browser it fills the page.
public struct WindowGroup<Content: View>: Scene {
    let title: String
    let id: String?
    let content: () -> Content

    public init(
        _ title: String = "Nucleant",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.id = nil
        self.content = content
    }

    /// A window group that `openWindow(id:)` opens a window from. Ids are
    /// unique among the app's `WindowGroup`s and `Window`s.
    public init(id: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = "Nucleant"
        self.id = id
        self.content = content
    }

    /// A titled window group that `openWindow(id:)` opens a window from.
    /// The title is its windows' and its New Window menu item's.
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = String(title)
        self.id = id
        self.content = content
    }

    public func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        [HostingWindow(title: title, root: content())]
    }

    public func _windowScenes<Node: NucleantContainerNode>(into scenes: inout [_WindowScene<Node>]) {
        scenes.append(_WindowScene(id: id, title: title, kind: .group) {
            self._makeWindows()
        })
    }

    public func _lowerCommands(into menuBar: MenuBar) {}
}
