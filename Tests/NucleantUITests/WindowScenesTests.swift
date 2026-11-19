//
//  WindowScenesTests.swift
//  NucleantUITests
//
//  An app's window scenes: the first one opens at launch and the others wait
//  to be asked for by id. A `WindowGroup` opens another window each time, a
//  `Window` one at most; views open and close them through the environment,
//  and the menu bar gets File › New Window and the Window menu's items.
//  Under it all, the trees of several windows standing at once each take
//  their own state changes, and none of another's.
//

import Testing
import NucleantWindow
@testable import NucleantUI

/// Opens the scene `opens` names as it appears, and closes its own window
/// when `closesItself`.
@View
struct WindowOpener {
    let opens: String?
    let closesItself: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.red
            .onAppear {
                if let opens { openWindow(id: opens) }
                if closesItself { dismissWindow() }
            }
    }
}

/// A main window group, a second group opened by id, and a unique window.
@MainActor
struct MailScenes {
    @SceneBuilder var body: some Scene {
        WindowGroup("Mail") { EmptyView() }
        WindowGroup("Message", id: "message") { EmptyView() }
            .defaultSize(width: 300, height: 200)
        Window("Connection Doctor", id: "doctor") { EmptyView() }
    }
}

/// A unique window declared before the group.
@MainActor
struct WindowFirstScenes {
    @SceneBuilder var body: some Scene {
        Window("Welcome", id: "welcome") { EmptyView() }
        WindowGroup("Mail") { EmptyView() }
    }
}

/// A window whose view opens a panel, and the panel, which closes itself.
@MainActor
struct OpenerScenes {
    @SceneBuilder var body: some Scene {
        WindowGroup("Main") { WindowOpener(opens: "panel", closesItself: false) }
        WindowGroup("Panel", id: "panel") { WindowOpener(opens: nil, closesItself: true) }
    }
}

/// A primitive scene that only makes its windows, as another package's
/// scene does.
struct OnlyMakesWindows: Scene {
    var body: Never { fatalError() }

    func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        [HostingWindow(title: "Plain", root: EmptyView())]
    }

    func _lowerCommands(into menuBar: MenuBar) {}
}

@MainActor
struct PlainScenes {
    @SceneBuilder var body: some Scene {
        OnlyMakesWindows()
        WindowGroup("Other", id: "other") { EmptyView() }
    }
}

/// Counts its taps, and logs each time its body runs.
@View
struct WindowTapCounter {
    let name: String
    let log: Log
    @State private var count = 0

    var body: some View {
        let _ = log("\(name) \(count)")
        Color.red.onTapGesture { count += 1 }
    }
}

/// The app's windows over `scene`, put on screen by noting their titles.
@MainActor
private func appWindows<S: Scene>(_ scene: S, presented: Log) -> AppWindows<NucleantRenderNode> {
    let windows = AppWindows<NucleantRenderNode>(scene)
    windows.present = { window in presented(window.title) }
    return windows
}

@MainActor
private func titles(_ windows: AppWindows<NucleantRenderNode>) -> [String] {
    windows.windows.map(\.window.title)
}

@MainActor
private func commandTitles(_ group: MenuBar.Group) -> [String] {
    group.items.compactMap { item in
        if case .command(let command) = item { command.title } else { nil }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct WindowScenesTests {

        @Test func onlyTheFirstSceneOpensAtLaunch() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            #expect(presented.take() == ["Mail"])
            #expect(titles(windows) == ["Mail"])
        }

        @Test func aWindowDeclaredFirstIsTheOneAtLaunch() {
            let presented = Log()
            let windows = appWindows(WindowFirstScenes().body, presented: presented)
            windows.launch()
            #expect(presented.take() == ["Welcome"])
        }

        @Test func aGroupOpensAnotherWindowEachTime() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            windows.openWindow(id: "message")
            windows.openWindow(id: "message")
            #expect(titles(windows) == ["Mail", "Message", "Message"])
            #expect(windows.windows[1].window !== windows.windows[2].window)
        }

        @Test func aWindowOpensOnceAndComesBackFreshAfterClosing() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            windows.openWindow(id: "doctor")
            windows.openWindow(id: "doctor")
            #expect(presented.take() == ["Mail", "Connection Doctor"])
            let first = windows.windows[1].window

            first.close()
            #expect(titles(windows) == ["Mail"])

            windows.openWindow(id: "doctor")
            #expect(presented.take() == ["Connection Doctor"])
            #expect(windows.windows[1].window !== first)
        }

        @Test func aPlatformWithOneWindowOpensNoOther() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.supportsMultipleWindows = false
            windows.launch()
            windows.openWindow(id: "message")
            windows.openWindow(id: "doctor")
            #expect(titles(windows) == ["Mail"])
            #expect(windows.windows[0].window.host.environment.supportsMultipleWindows == false)
        }

        @Test func theWindowsSayWhetherMoreCanOpen() {
            let windows = appWindows(MailScenes().body, presented: Log())
            windows.launch()
            #expect(windows.windows[0].window.host.environment.supportsMultipleWindows
                == HostingWindow<NucleantRenderNode>.supportsMultipleWindows)
        }

        @Test func anUnknownIdOpensNothing() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            windows.openWindow(id: "nowhere")
            #expect(titles(windows) == ["Mail"])
        }

        @Test func dismissingAGroupClosesEachOfItsWindows() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            windows.openWindow(id: "message")
            windows.openWindow(id: "message")
            windows.openWindow(id: "doctor")
            windows.dismissWindow(id: "message")
            #expect(titles(windows) == ["Mail", "Connection Doctor"])
        }

        @Test func aSceneSizesTheWindowsItOpensLater() {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            windows.openWindow(id: "message")
            #expect(windows.windows[1].window.sizing.defaultSize == Size(width: 300, height: 200))
            #expect(windows.windows[0].window.sizing.defaultSize == nil)
        }

        @Test func aSceneThatOnlyMakesWindowsOpensAtLaunchAndFromNoMenu() {
            let presented = Log()
            let windows = appWindows(PlainScenes().body, presented: presented)
            windows.launch()
            #expect(presented.take() == ["Plain"])
            let menuBar = MenuBar()
            windows.lowerCommands(into: menuBar)
            #expect(menuBar.groups.map(commandTitles) == [["New Window"]])
        }

        @Test func viewsOpenAndCloseWindowsThroughTheEnvironment() {
            let presented = Log()
            let windows = appWindows(OpenerScenes().body, presented: presented)
            windows.launch()
            let main = windows.windows[0].window.host
            main.setSize(Size(width: 100, height: 100))
            main.update()
            #expect(titles(windows) == ["Main", "Panel"])

            // The panel's view closes its own window, and only that one.
            let panel = windows.windows[1].window.host
            panel.setSize(Size(width: 100, height: 100))
            panel.update()
            #expect(titles(windows) == ["Main"])
        }

        @Test func theMenuBarOpensEachScene() throws {
            let presented = Log()
            let windows = appWindows(MailScenes().body, presented: presented)
            windows.launch()
            let menuBar = MenuBar()
            windows.lowerCommands(into: menuBar)
            #expect(menuBar.menus.isEmpty)
            #expect(menuBar.groups.count == 2)

            let newItems = try #require(menuBar.groups.first)
            #expect(newItems.placement == .newItem)
            #expect(newItems.position == .replacing)
            #expect(commandTitles(newItems) == ["New Mail Window", "New Message Window"])
            guard case .command(let newMail) = newItems.items[0],
                  case .command(let newMessage) = newItems.items[1] else {
                Issue.record("New Window items are commands")
                return
            }
            #expect(newMail.shortcut == MenuBar.Shortcut("n"))
            #expect(newMessage.shortcut == nil)

            let windowItems = menuBar.groups[1]
            #expect(windowItems.placement == .windowArrangement)
            #expect(windowItems.position == .after)
            #expect(commandTitles(windowItems) == ["Connection Doctor"])

            newMessage.action()
            guard case .command(let doctor) = windowItems.items[0] else { return }
            doctor.action()
            doctor.action()
            #expect(titles(windows) == ["Mail", "Message", "Connection Doctor"])
        }

        @Test func oneGroupIsNewWindow() {
            let windows = appWindows(WindowFirstScenes().body, presented: Log())
            let menuBar = MenuBar()
            windows.lowerCommands(into: menuBar)
            #expect(menuBar.groups.map(commandTitles) == [["New Window"], ["Welcome"]])
        }

        /// Two windows' trees, each with its state at the same path: a tap
        /// in one, then a frame of the other before its own. The other's
        /// frame finds nothing to do, and the tapped one's finds its change.
        @Test func twoTreesTakeOnlyTheirOwnChanges() {
            let log = Log()
            let first = Harness(WindowTapCounter(name: "first", log: log))
            let second = Harness(WindowTapCounter(name: "second", log: log))
            #expect(log.take() == ["first 0", "second 0"])

            first.host.pointerDown(id: 0, at: center)
            first.host.pointerUp(id: 0, at: center)
            second.host.update()
            #expect(log.take() == [])

            first.host.update()
            #expect(log.take() == ["first 1"])
        }
    }
}
