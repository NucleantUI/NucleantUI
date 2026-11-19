//
//  SystemTrayTests.swift
//  NucleantUITests
//
//  `SystemTray`: what its item shows and does, kept up to date with what
//  the app's body read for it; `isInserted` putting it up and taking it
//  away; its window in the `.window` style; and its place among the app's
//  scenes — first, it opens no window at launch, and the app goes on with
//  none open.
//

import Foundation
import Observation
import Testing
import NucleantWindow
@testable import NucleantUI

@MainActor
@Observable
final class TrayModel {
    var running = false
    var shown = true
}

/// A timer in the tray, declared before a window group.
@MainActor
struct TimerTrayScenes {
    let model: TrayModel

    @SceneBuilder var body: some Scene {
        SystemTray(model.running ? "Running" : "Idle", systemImage: "timer") {
            Button(model.running ? "Pause" : "Start") { model.running.toggle() }
            Divider()
            Button("Reset") {}
        }
        WindowGroup("Main", id: "main") { EmptyView() }
    }
}

/// A window group first, and a tray that comes and goes with `shown`.
@MainActor
struct OptionalTrayScenes {
    let model: TrayModel

    @SceneBuilder var body: some Scene {
        WindowGroup("Main") { EmptyView() }
        SystemTray("Timer", isInserted: Binding(get: { model.shown }, set: { model.shown = $0 })) {
            Button("Start") {}
        }
    }
}

/// A tray with a window, sized by the scene; inside a style it overrides.
@MainActor
struct WindowTrayScenes {
    @SceneBuilder var body: some Scene {
        SystemTray("Panel") {
            Text("Hello")
        }
        .systemTrayStyle(.window)
        .defaultSize(width: 200, height: 100)
        .systemTrayStyle(.menu)
    }
}

/// A label of an image with a title beside it.
@MainActor
struct LabelledTrayScenes {
    static let dot = RasterImage(width: 2, height: 2, pixels: [UInt32](repeating: 0xFF00_0000, count: 4))

    @SceneBuilder var body: some Scene {
        SystemTray {
            Button("Open") {}
        } label: {
            HStack {
                Image(Self.dot)
                Text("Clock")
            }
        }
    }
}

struct TrayOnlyApp: NucleantApp {
    var body: some Scene {
        SystemTray("Only", systemImage: "star") { Button("Quit") {} }
    }
}

/// A window first, a tray after it: the World Clock's shape.
struct WindowAndTrayApp: NucleantApp {
    var body: some Scene {
        Window("Main", id: "main") { EmptyView() }
        SystemTray("Tray", systemImage: "star") { Button("Open") {} }
    }
}

/// A tray that keeps the Dock icon, said inside a group of scenes.
@MainActor
struct DockShownScenes {
    @SceneBuilder var body: some Scene {
        SystemTray("Tray", systemImage: "star") { Button("Open") {} }
            .dockIcon(.visible)
        WindowGroup("Main") { EmptyView() }
            .dockIcon(.hidden)
    }
}

struct WindowOnlyApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Only") { EmptyView() }
    }
}

/// The platform's tray, recording what it is asked to do.
@MainActor
private final class FakeTray {
    var shown: [TrayItem] = []
    var log: [String] = []
    var quits = 0
    var presented: [String] = []

    func trays<S: Scene>(_ scene: @escaping @MainActor () -> S) -> AppSystemTrays<NucleantRenderNode> {
        let trays = AppSystemTrays<NucleantRenderNode> {
            var scenes = _AppScenes<NucleantRenderNode>()
            scene()._scenes(into: &scenes)
            return scenes.systemTrays
        }
        trays.insert = { [unowned self] item in shown.append(item); log.append("insert \(item.title)") }
        trays.refresh = { [unowned self] item in log.append("refresh \(item.title)") }
        trays.remove = { [unowned self] item in shown.removeAll { $0 === item }; log.append("remove \(item.title)") }
        trays.quit = { [unowned self] in quits += 1 }
        trays.present = { [unowned self] window in presented.append(window.title) }
        return trays
    }

    func take() -> [String] {
        defer { log = [] }
        return log
    }
}

@MainActor
private func rowTitles(_ item: TrayItem) -> [String]? {
    guard case .menu(let rows) = item.action else { return nil }
    return rows.compactMap { row in
        if case .command(let command) = row { command.title } else { nil }
    }
}

/// Let the observation's change reach the trays.
@MainActor
private func settle() async {
    try? await Task.sleep(for: .milliseconds(20))
}

extension HostedViews {
    @MainActor
    @Suite
    struct SystemTrayTests {

        @Test func aTrayFirstOpensNoWindowAtLaunch() {
            let presented = Log()
            let windows = AppWindows<NucleantRenderNode>(TimerTrayScenes(model: TrayModel()).body)
            windows.present = { presented($0.title) }
            windows.launch()
            #expect(presented.take() == [])
            #expect(windows.scenes.map(\.title) == ["Main"])
        }

        @Test func aWindowFirstStillOpensWithATrayAfterIt() {
            let presented = Log()
            let windows = AppWindows<NucleantRenderNode>(OptionalTrayScenes(model: TrayModel()).body)
            windows.present = { presented($0.title) }
            windows.launch()
            #expect(presented.take() == ["Main"])
        }

        @Test func theItemShowsTheTitleTheIconAndTheMenu() throws {
            let tray = FakeTray()
            let model = TrayModel()
            let trays = tray.trays { TimerTrayScenes(model: model).body }
            trays.start()
            #expect(tray.take() == ["insert Idle"])
            let item = try #require(tray.shown.first)
            #expect(item.iconName == "timer")
            #expect(item.showsTitle == false)
            #expect(rowTitles(item) == ["Start", "Reset"])
        }

        @Test func whatTheBodyReadChangingReachesTheItem() async throws {
            let tray = FakeTray()
            let model = TrayModel()
            let trays = tray.trays { TimerTrayScenes(model: model).body }
            trays.start()
            _ = tray.take()

            model.running = true
            await settle()
            #expect(tray.take() == ["refresh Running"])
            let item = try #require(tray.shown.first)
            #expect(rowTitles(item) == ["Pause", "Reset"])

            // A row's action runs the app's code, and the item follows.
            guard case .menu(let rows) = item.action, case .command(let pause) = rows[0] else {
                Issue.record("the first row is a command")
                return
            }
            pause.action()
            await settle()
            #expect(model.running == false)
            #expect(item.title == "Idle")
        }

        @Test func isInsertedPutsTheItemUpAndTakesItAway() async {
            let tray = FakeTray()
            let model = TrayModel()
            let trays = tray.trays { OptionalTrayScenes(model: model).body }
            trays.start()
            #expect(tray.take() == ["insert Timer"])

            model.shown = false
            await settle()
            #expect(tray.take() == ["remove Timer"])
            #expect(tray.shown.isEmpty)

            model.shown = true
            await settle()
            #expect(tray.take() == ["insert Timer"])
        }

        @Test func takingTheItemOutSetsItsBinding() async throws {
            let tray = FakeTray()
            let model = TrayModel()
            let trays = tray.trays { OptionalTrayScenes(model: model).body }
            trays.start()
            let item = try #require(tray.shown.first)
            _ = tray.take()

            // The host took it away already; the app only hears of it.
            #expect(trays.hasInsertedItem)
            item.onRemove?()
            #expect(model.shown == false)
            #expect(trays.hasInsertedItem == false)
            await settle()
            #expect(tray.take() == [])
            #expect(tray.quits == 0)
        }

        @Test func takingOutATrayWithNoBindingQuits() throws {
            let tray = FakeTray()
            let trays = tray.trays { TimerTrayScenes(model: TrayModel()).body }
            trays.start()
            let item = try #require(tray.shown.first)
            item.onRemove?()
            #expect(tray.quits == 1)
        }

        @Test func theWindowStyleOpensItsWindowOnceOnPress() throws {
            let tray = FakeTray()
            let trays = tray.trays { WindowTrayScenes().body }
            trays.start()
            let item = try #require(tray.shown.first)
            guard case .press(let press) = item.action else {
                Issue.record("a .window tray is pressed, not a menu")
                return
            }
            let anchor = TrayAnchor(x: 100, y: 800, width: 24, height: 22)
            press(anchor)
            press(anchor)
            #expect(tray.presented == ["Panel"])
            let panel = try #require(trays.slots[0].panel)
            #expect(panel.isTrayPanel)
            #expect(panel.sizing.defaultSize == Size(width: 200, height: 100))
        }

        @Test func aLabelOfAnImageAndTextShowsBoth() throws {
            let tray = FakeTray()
            let trays = tray.trays { LabelledTrayScenes().body }
            trays.start()
            let item = try #require(tray.shown.first)
            #expect(item.title == "Clock")
            #expect(item.showsTitle)
            #expect(item.icon?.width == 2)
            #expect(item.icon?.pixels == LabelledTrayScenes.dot.pixels)
        }

        @Test func aTrayAppHasTheDockIconWhileAWindowIsOpen() {
            var scenes = _AppScenes<NucleantRenderNode>()
            TimerTrayScenes(model: TrayModel()).body._scenes(into: &scenes)
            #expect(scenes.dockIcon == nil)
            #expect(scenes.showsDockIcon(hasOpenWindow: false) == false)
            #expect(scenes.showsDockIcon(hasOpenWindow: true) == true)

            var plain = _AppScenes<NucleantRenderNode>()
            WindowOnlyApp().body._scenes(into: &plain)
            #expect(plain.showsDockIcon(hasOpenWindow: false) == true)
        }

        @Test func dockIconSaysOtherwiseAndTheFirstOneWins() {
            var scenes = _AppScenes<NucleantRenderNode>()
            DockShownScenes().body._scenes(into: &scenes)
            #expect(scenes.dockIcon == .visible)
            #expect(scenes.showsDockIcon(hasOpenWindow: false) == true)

            var hidden = _AppScenes<NucleantRenderNode>()
            TimerTrayScenes(model: TrayModel()).body.dockIcon(.hidden)._scenes(into: &hidden)
            #expect(hidden.showsDockIcon(hasOpenWindow: true) == false)
        }

        @Test func anAppStartingInTheTrayStartsWithNoDockIcon() {
            #expect(AppRuntime(app: TrayOnlyApp()).showsDockIconAtLaunch == false)
            #expect(AppRuntime(app: WindowAndTrayApp()).showsDockIconAtLaunch == true)
            #expect(AppRuntime(app: WindowOnlyApp()).showsDockIconAtLaunch == true)
        }

        @Test func theWindowsSayWhenOneOpensOrCloses() {
            let changes = Log()
            let windows = AppWindows<NucleantRenderNode>(WindowAndTrayApp().body)
            windows.present = { _ in }
            windows.onWindowsChange = { [unowned windows] in changes("\(windows.windows.count)") }
            windows.launch()
            windows.windows[0].window.close()
            #expect(changes.take() == ["1", "0"])
        }

        @Test func anAppWithATrayGoesOnWithNoWindow() {
            #expect(AppRuntime(app: TrayOnlyApp()).terminatesAfterLastWindowClosed == false)
            #expect(AppRuntime(app: WindowOnlyApp()).terminatesAfterLastWindowClosed == true)
        }
    }
}
