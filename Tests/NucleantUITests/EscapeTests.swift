//
//  EscapeTests.swift
//  NucleantUITests
//
//  Escape closing what is open over the window, one thing per press, the
//  top one first: a menu (a `.contextMenu`, a `Menu`'s dropdown) before
//  any view, then the innermost popover, its binding set false, unless a
//  view's `.onKeyPress` keeps the key.
//

import Observation
import Testing
@testable import NucleantUI

/// Which of a test's popovers are open, changed by the tests and by the
/// popovers' bindings.
@MainActor
@Observable
final class Popovers {
    var isOuterShown = false
    var isInnerShown = false
}

/// Where a test's `Menu` was placed, in window coordinates.
@MainActor
final class MenuProbe {
    var frame = Rect.zero

    var center: Point { Point(x: frame.midX, y: frame.midY) }

    /// The first row of the menu the `Menu` opens, under the control.
    var firstRow: Point {
        HostedViews.ContextMenuTests.firstRow(of: Point(x: frame.minX, y: frame.maxY + 2))
    }
}

/// A `Menu` in the top leading corner; its one row logs.
@View
struct EscapeMenu {
    let log: Log
    let probe: MenuProbe

    var body: some View {
        Menu("Presets") {
            Button("Mute") { log("mute") }
        }
        .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { probe.frame = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A square with a popover on it, holding a `Menu` and a square with a
/// popover of its own.
@View
struct EscapePopovers {
    @Bindable var popovers: Popovers
    let log: Log
    let probe: MenuProbe

    var body: some View {
        Color.gray
            .frame(width: 40, height: 40)
            .popover(isPresented: $popovers.isOuterShown) {
                HStack {
                    Menu("Presets") {
                        Button("Mute") { log("mute") }
                    }
                    .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { probe.frame = $0 }
                    Color.blue
                        .frame(width: 20, height: 20)
                        .popover(isPresented: $popovers.isInnerShown) {
                            Text("Inner")
                        }
                }
            }
    }
}

/// A square that takes the keys and keeps Escape for itself, with a
/// popover and a context menu on it.
@View
struct EscapeKeeper {
    @Bindable var popovers: Popovers
    let log: Log

    var body: some View {
        Color.orange
            .frame(width: 40, height: 40)
            .focusable()
            .onKeyPress(.escape) {
                log("kept")
                return .handled
            }
            .contextMenu {
                Button("Copy") { log("copy") }
            }
            .popover(isPresented: $popovers.isOuterShown) {
                Text("Options")
            }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct EscapeTests {

        static let size = Size(width: 400, height: 400)

        // MARK: Menus

        @Test func escapeClosesAContextMenu() async {
            let log = Log()
            let harness = Harness(PlainContextMenu(log: log))
            let click = Point(x: 70, y: 60)
            let row = ContextMenuTests.firstRow(of: click)

            harness.host.secondaryClick(at: click)
            await harness.settle()
            await harness.key(KeyCode.escape)
            await harness.tap(row)
            #expect(log.take() == [], "the menu was closed")

            harness.host.secondaryClick(at: click)
            await harness.settle()
            await harness.tap(row)
            #expect(log.take() == ["duplicate"], "the row is where the tap went")
        }

        @Test func escapeClosesAMenusDropdown() async {
            let log = Log()
            let probe = MenuProbe()
            let harness = Harness(EscapeMenu(log: log, probe: probe))

            await harness.tap(probe.center)
            await harness.key(KeyCode.escape)
            await harness.tap(probe.firstRow)
            #expect(log.take() == [], "the menu was closed")

            await harness.tap(probe.center)
            await harness.tap(probe.firstRow)
            #expect(log.take() == ["mute"], "the row is where the tap went")
        }

        @Test func anOpenMenuTakesEscapeBeforeTheViewWithTheKeys() async {
            let log = Log()
            let popovers = Popovers()
            let harness = Harness(EscapeKeeper(popovers: popovers, log: log), size: Self.size)
            let square = Point(x: 200, y: 200)
            await harness.tap(square)

            harness.host.secondaryClick(at: square)
            await harness.settle()
            await harness.key(KeyCode.escape)
            #expect(log.take() == [], "the menu took it")

            // The menu is closed, or this one would go to it as well.
            await harness.key(KeyCode.escape)
            #expect(log.take() == ["kept"], "with no menu open, the view's own")
        }

        // MARK: Popovers

        @Test func escapeClosesThePopoverAndSetsItsBindingFalse() async {
            let popovers = Popovers()
            popovers.isOuterShown = true
            let harness = Harness(EscapePopovers(popovers: popovers, log: Log(), probe: MenuProbe()), size: Self.size)
            await harness.settle()

            await harness.key(KeyCode.escape)
            #expect(popovers.isOuterShown == false)
        }

        @Test func escapeClosesTheInnermostPopoverFirst() async {
            let popovers = Popovers()
            popovers.isOuterShown = true
            popovers.isInnerShown = true
            let harness = Harness(EscapePopovers(popovers: popovers, log: Log(), probe: MenuProbe()), size: Self.size)
            await harness.settle()

            await harness.key(KeyCode.escape)
            #expect(popovers.isInnerShown == false)
            #expect(popovers.isOuterShown == true)

            await harness.key(KeyCode.escape)
            #expect(popovers.isOuterShown == false)
        }

        @Test func aHeldEscapeClosesOneThing() async {
            let popovers = Popovers()
            popovers.isOuterShown = true
            popovers.isInnerShown = true
            let harness = Harness(EscapePopovers(popovers: popovers, log: Log(), probe: MenuProbe()), size: Self.size)
            await harness.settle()

            // Down, then the platform's repeats, then up.
            harness.host.keyDown(keyCode: KeyCode.escape, characters: nil)
            await harness.settle()
            harness.host.keyDown(keyCode: KeyCode.escape, characters: nil)
            await harness.settle()
            harness.host.keyUp(keyCode: KeyCode.escape, characters: nil)
            await harness.settle()
            #expect(popovers.isInnerShown == false)
            #expect(popovers.isOuterShown == true)
        }

        @Test func escapeClosesAMenuBeforeThePopoverItOpenedFrom() async {
            let log = Log()
            let probe = MenuProbe()
            let popovers = Popovers()
            popovers.isOuterShown = true
            let harness = Harness(EscapePopovers(popovers: popovers, log: log, probe: probe), size: Self.size)
            await harness.settle()

            // A row runs its action and closes the menu, not the popover.
            await harness.tap(probe.center)
            await harness.tap(probe.firstRow)
            #expect(log.take() == ["mute"], "the row is where the tap went")
            #expect(popovers.isOuterShown == true)

            await harness.tap(probe.center)
            await harness.key(KeyCode.escape)
            #expect(popovers.isOuterShown == true, "the menu closed, not the popover")

            await harness.key(KeyCode.escape)
            #expect(popovers.isOuterShown == false)
            await harness.tap(probe.firstRow)
            #expect(log.take() == [], "the menu was closed")
        }

        @Test func aViewsOnKeyPressKeepsEscapeFromThePopover() async {
            let log = Log()
            let popovers = Popovers()
            let harness = Harness(EscapeKeeper(popovers: popovers, log: log), size: Self.size)
            await harness.tap(Point(x: 200, y: 200))
            popovers.isOuterShown = true
            await harness.settle()

            await harness.key(KeyCode.escape)
            #expect(log.take() == ["kept"])
            #expect(popovers.isOuterShown == true)
        }
    }
}
