//
//  SystemTray.swift
//  NucleantUI
//
//  `SystemTray`: an app's item in the system tray — on macOS one of the
//  icons at the right end of the menu bar, what SwiftUI calls a
//  `MenuBarExtra`. Its content is a menu that drops down from it, or, in
//  the `.window` style, a window under it with any views in it. The app
//  keeps the item up to date (`AppSystemTrays`): what the body read for it
//  changes, the item changes.
//

import NucleantVulkan
import NucleantWindow

/// A scene that shows itself as an item in the system tray — on macOS, in
/// the menu bar.
///
/// ```swift
/// @main
/// struct Timer: NucleantApp {
///     var body: some Scene {
///         SystemTray("Timer", systemImage: "timer") {
///             Button("Start") { model.start() }
///             Button("Reset") { model.reset() }
///             Divider()
///             Button("Quit Timer") { Self.quit() }
///         }
///     }
/// }
/// ```
///
/// The content is a menu: `Button`s are its rows, `Divider` a rule, and
/// `Group`, `ForEach` and `if` work as in any builder — the same rows a
/// `CommandMenu` takes. With `.systemTrayStyle(.window)` it is any views
/// instead, in a window that drops down from the item and goes away when
/// the app is clicked out of.
///
/// Declared first, it is the app's main scene: the app opens no window at
/// launch, keeps running with no window open, and quits when the person
/// takes the item out of the tray. With `isInserted`, it is one scene
/// among others: the item is there while the binding is `true`, and taking
/// it out sets it `false`.
///
/// An app with one is in the Dock while one of its windows is open, and in
/// the tray alone once they are closed; `.dockIcon(_:)` says otherwise.
///
/// On macOS for now. Elsewhere the app logs that it shows no tray.
public struct SystemTray<Label: View, Content: View>: Scene {
    let title: String
    let systemImage: String?
    let label: Label?
    let isInserted: Binding<Bool>?
    let content: Content

    /// An item shown by `label`. The label is a `Text`, an `Image`, or both
    /// (in a stack, a `Group`): the text, the image, or the image and the
    /// text beside it.
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.title = ""
        self.systemImage = nil
        self.isInserted = nil
        self.content = content()
    }

    /// An item shown by `label`, there while `isInserted` is `true`.
    public init(isInserted: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.title = ""
        self.systemImage = nil
        self.isInserted = isInserted
        self.content = content()
    }

    public func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        []
    }

    public func _scenes<Node: NucleantContainerNode>(into scenes: inout _AppScenes<Node>) {
        var shown = SystemTrayLabel(title: title.isEmpty ? nil : title, image: nil)
        if let label {
            systemTrayLabel(of: label, into: &shown)
        }
        let title = shown.title ?? ""
        let content = self.content
        scenes.append(_SystemTrayScene(
            title: title,
            systemImage: systemImage,
            image: shown.image,
            // A label of both is shown as both; a title next to a system
            // image is for accessibility.
            showsTitle: label != nil && shown.title != nil && shown.image != nil,
            isInserted: isInserted,
            usesWindow: nil,
            menuItems: menuItems(of: content),
            makePanel: { HostingWindow(title: title, root: content) }
        ))
    }

    public func _lowerCommands(into menuBar: MenuBar) {}
}

extension SystemTray where Label == Text {
    /// An item shown by its title.
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.title = String(title)
        self.systemImage = nil
        self.label = nil
        self.isInserted = nil
        self.content = content()
    }

    /// An item shown by its title, there while `isInserted` is `true`.
    public init<S: StringProtocol>(_ title: S, isInserted: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = String(title)
        self.systemImage = nil
        self.label = nil
        self.isInserted = isInserted
        self.content = content()
    }

    /// An item shown by one of the platform's own icons — an SF Symbol name
    /// on macOS — with `title` for accessibility.
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = String(title)
        self.systemImage = systemImage
        self.label = nil
        self.isInserted = nil
        self.content = content()
    }

    /// An item shown by one of the platform's own icons, there while
    /// `isInserted` is `true`.
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        isInserted: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = String(title)
        self.systemImage = systemImage
        self.label = nil
        self.isInserted = isInserted
        self.content = content()
    }
}

// MARK: - Style

/// How a `SystemTray` shows its content.
public protocol SystemTrayStyle {}

/// The platform's choice: a menu.
public struct AutomaticSystemTrayStyle: SystemTrayStyle {
    public init() {}
}

/// A menu that drops down from the item.
public struct PullDownSystemTrayStyle: SystemTrayStyle {
    public init() {}
}

/// A window that drops down from the item, holding the content as views.
public struct WindowSystemTrayStyle: SystemTrayStyle {
    public init() {}
}

extension SystemTrayStyle where Self == AutomaticSystemTrayStyle {
    public static var automatic: AutomaticSystemTrayStyle { AutomaticSystemTrayStyle() }
}

extension SystemTrayStyle where Self == PullDownSystemTrayStyle {
    /// The content as a menu that drops down from the item.
    public static var menu: PullDownSystemTrayStyle { PullDownSystemTrayStyle() }
}

extension SystemTrayStyle where Self == WindowSystemTrayStyle {
    /// The content as views, in a window that drops down from the item and
    /// goes away when the app is clicked out of.
    public static var window: WindowSystemTrayStyle { WindowSystemTrayStyle() }
}

extension Scene {
    /// How the `SystemTray`s in this scene show their content: as a menu,
    /// or in a window. The one nearest the tray wins.
    public func systemTrayStyle<S: SystemTrayStyle>(_ style: S) -> some Scene {
        SystemTrayStyleScene(base: self, usesWindow: S.self == WindowSystemTrayStyle.self)
    }
}

/// `.systemTrayStyle(_:)`: the scene it wraps, its trays in a style.
struct SystemTrayStyleScene<Base: Scene>: Scene {
    let base: Base
    let usesWindow: Bool

    var body: Never { fatalError() }

    func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        base._makeWindows()
    }

    func _scenes<Node: NucleantContainerNode>(into scenes: inout _AppScenes<Node>) {
        var inner = _AppScenes<Node>()
        base._scenes(into: &inner)
        let usesWindow = self.usesWindow
        inner.mapSystemTrays { tray in
            var tray = tray
            if tray.usesWindow == nil { tray.usesWindow = usesWindow }
            return tray
        }
        scenes.append(contentsOf: inner)
    }

    func _lowerCommands(into menuBar: MenuBar) {
        base._lowerCommands(into: menuBar)
    }
}

// MARK: - As the app keeps it

/// One `SystemTray`, as the app keeps it: what the item shows, and what its
/// content is in either style.
@MainActor
public struct _SystemTrayScene<Node: NucleantContainerNode> {
    public let title: String
    public let systemImage: String?
    public let image: RasterImage?
    /// The title beside the icon, not only for accessibility.
    public let showsTitle: Bool
    /// `nil` for an item that is always there.
    public let isInserted: Binding<Bool>?
    /// In a window (`.window`), as a menu (`.menu`), or — `nil` — as the
    /// platform likes: a menu.
    public var usesWindow: Bool?
    /// The content as menu rows.
    public let menuItems: [MenuBar.Item]
    /// The content in a window, for the `.window` style.
    public var makePanel: @MainActor () -> HostingWindow<Node>
}

// MARK: - Label

/// What a tray item's label view shows: its text, its image.
struct SystemTrayLabel {
    var title: String?
    var image: RasterImage?
}

/// A view that can be a tray item's label, or hold one. Read from stored
/// fields only — no `body` is asked for, as for menu rows (`MenuItems`).
@MainActor
protocol SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel)
}

@MainActor
func systemTrayLabel<V: View>(of view: V, into label: inout SystemTrayLabel) {
    (view as? SystemTrayLabelSource)?._systemTrayLabel(into: &label)
}

extension Text: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        if label.title == nil { label.title = content }
    }
}

extension Image: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        if label.image == nil { label.image = image }
    }
}

extension TupleView: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        for view in repeat (each value) {
            systemTrayLabel(of: view, into: &label)
        }
    }
}

extension HStack: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        systemTrayLabel(of: content, into: &label)
    }
}

extension Group: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        systemTrayLabel(of: content, into: &label)
    }
}

extension _ModifierView: SystemTrayLabelSource {
    func _systemTrayLabel(into label: inout SystemTrayLabel) {
        systemTrayLabel(of: content, into: &label)
    }
}
