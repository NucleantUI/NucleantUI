//
//  WindowGroup.swift
//  NucleantUI
//

import NucleantWindow

/// A scene that presents one window over a view hierarchy.
///
/// The window's size isn't an input: `defaultSize(width:height:)` says what
/// it opens at, `windowResizability(_:)` how its content limits it, and
/// `windowIdealSize(_:)` what zooming does. Without them a desktop window
/// opens at 900 × 600 and can't be made smaller than its content; in a
/// browser it fills the page.
public struct WindowGroup<Content: View>: Scene {
    let title: String
    let content: () -> Content

    public init(
        _ title: String = "Nucleant",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    public func _makeWindows() -> [HostingWindow] {
        [HostingWindow(title: title, root: content())]
    }

    public func _lowerCommands(into menuBar: MenuBar) {}
}
