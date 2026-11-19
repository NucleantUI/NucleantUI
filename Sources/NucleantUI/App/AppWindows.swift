//
//  AppWindows.swift
//  NucleantUI
//
//  The app's window scenes, and the windows open from them. At launch the
//  first scene the app declares opens its window and the others wait: a
//  scene with an id opens when a view asks for it (`openWindow(id:)`), and
//  from the menu bar — File › New Window for a `WindowGroup`, its title in
//  the Window menu for a `Window`.
//

import NucleantVulkan
import NucleantWindow

@MainActor
final class AppWindows<Node: NucleantContainerNode> {
    /// The window scenes, in the order the app declares them.
    let scenes: [_WindowScene<Node>]

    /// Whether the app's first scene is one of these, and opens at launch.
    let opensWindowAtLaunch: Bool

    /// The windows open now, in the order they opened, each with the index
    /// of the scene it is from.
    private(set) var windows: [(scene: Int, window: HostingWindow<Node>)] = [] {
        didSet { onWindowsChange?() }
    }

    /// Told when a window opens or closes — the Dock icon follows them.
    var onWindowsChange: (@MainActor () -> Void)?

    /// Brings a window made from a scene up on screen. The runtime's puts
    /// it on the app's GPU device first.
    var present: @MainActor (HostingWindow<Node>) throws -> Void = { try $0.present() }

    init<S: Scene>(_ scene: S) {
        var scenes = _AppScenes<Node>()
        scene._scenes(into: &scenes)
        self.scenes = scenes.windows
        self.opensWindowAtLaunch = scenes.opensWindowAtLaunch
    }

    /// What the app shows at launch: the first scene's window, when the
    /// first scene is a window scene.
    func launch() {
        guard opensWindowAtLaunch else { return }
        open(scene: 0)
    }

    /// A window from the scene whose id is `id`: another from a
    /// `WindowGroup`, the `Window` — or, when it is open, the `Window`
    /// brought to the front.
    func openWindow(id: String) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else {
            nucleantLogError("NucleantUI: openWindow(id: \"\(id)\"): no WindowGroup or Window has that id\n")
            return
        }
        open(scene: index)
    }

    /// Close the windows of the scene whose id is `id`.
    func dismissWindow(id: String) {
        for (scene, window) in windows where scenes[scene].id == id {
            window.close()
        }
    }

    /// Whether this platform shows more than the app's first window.
    var supportsMultipleWindows = HostingWindow<Node>.supportsMultipleWindows

    func open(scene index: Int) {
        if scenes[index].kind == .unique, let open = windows.first(where: { $0.scene == index }) {
            open.window.bringToFront()
            return
        }
        guard windows.isEmpty || supportsMultipleWindows else {
            nucleantLogError("NucleantUI: \"\(scenes[index].title)\" not opened: the app has one window on this platform\n")
            return
        }
        for window in scenes[index].makeWindows() {
            wire(window) { [weak window] in window?.close() }
            // Closed, it goes: its engine, its tree, its state.
            window.onClose = { [weak self, weak window] in
                self?.windows.removeAll { $0.window === window }
            }
            windows.append((index, window))
            do {
                try present(window)
            } catch {
                windows.removeAll { $0.window === window }
                nucleantLogError("NucleantUI: window present failed: \(error)\n")
            }
        }
    }

    /// Hand `window`'s views the actions that open and close the app's
    /// windows; `dismiss` is what closing the window they are in does.
    func wire(_ window: HostingWindow<Node>, dismiss: @escaping @MainActor @Sendable () -> Void) {
        window.host.environment.supportsMultipleWindows = supportsMultipleWindows
        window.host.environment.openWindow = OpenWindowAction { [weak self] id in
            self?.openWindow(id: id)
        }
        window.host.environment.dismissWindow = DismissWindowAction(
            dismiss: dismiss,
            dismissID: { [weak self] id in self?.dismissWindow(id: id) }
        )
    }

    // MARK: - Menu bar

    /// The menu items that open the scenes: File › New Window for each
    /// `WindowGroup` — "New Window" when there is one, "New <title> Window"
    /// each when there are more, ⌘N on the first — and each `Window` by its
    /// title in the Window menu. `CommandGroup(replacing: .newItem)` takes
    /// the New Window items away, as any `.commands` lowered after these.
    func lowerCommands(into menuBar: MenuBar) {
        let groups = scenes.indices.filter { scenes[$0].kind == .group }
        let newItems: [MenuBar.Item] = groups.enumerated().map { position, index in
            .command(MenuBar.Command(
                title: groups.count == 1 ? "New Window" : "New \(scenes[index].title) Window",
                shortcut: position == 0 ? MenuBar.Shortcut("n") : nil,
                action: { [weak self] in self?.open(scene: index) }
            ))
        }
        if !newItems.isEmpty {
            menuBar.groups.append(MenuBar.Group(.newItem, position: .replacing, items: newItems))
        }

        let windowItems: [MenuBar.Item] = scenes.indices.filter { scenes[$0].kind == .unique }.map { index in
            .command(MenuBar.Command(
                title: scenes[index].title,
                action: { [weak self] in self?.open(scene: index) }
            ))
        }
        if !windowItems.isEmpty {
            menuBar.groups.append(MenuBar.Group(.windowArrangement, position: .after, items: windowItems))
        }
    }
}
