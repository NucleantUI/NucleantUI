//
//  WindowInputTests.swift
//  NucleantUITests
//
//  A window's `WindowInputDelegate`: it hears the window's events that no
//  view takes — what a view draws on top keeps its own — and keeps from the
//  views what it takes; the window's views find it through `\.windowInput`.
//
//  The events go in at y = 100 of a 200-point-high window, where AppKit's
//  bottom-up y and the views' top-down one agree.
//

import Foundation
import Testing
@testable import NucleantUI

// MARK: - Views and delegates

/// A tap target on the left half, nothing that takes a press on the right.
@View
struct TapBesideOpenSpace {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Color.red.frame(width: 100).onTapGesture { log("tap") }
            Color.clear.frame(width: 100)
        }
    }
}

/// A 50-point tap target in the middle, drawn over open space.
@View
struct TapOnTop {
    let log: Log

    var body: some View {
        ZStack {
            Color.clear
            Color.blue.frame(width: 50, height: 50).onTapGesture { log("on top") }
        }
    }
}

/// A view that takes the keys on the left half, open space on the right.
@View
struct FocusableBesideOpenSpace {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Color.green.frame(width: 100).focusable(onFocusChange: { log("focus \($0)") })
            Color.clear.frame(width: 100)
        }
    }
}

/// Keeps what `\.windowInput` held when the view was built.
@MainActor
final class InputBox {
    var input: WindowInput?
}

@View
struct ReadsWindowInput {
    let box: InputBox
    @Environment(\.windowInput) var windowInput

    var body: some View {
        let _ = box.input = windowInput
        Color.red
    }
}

/// Logs the touches, the mouse moves and the scrolls; takes them when
/// `takes`.
@MainActor
final class InputLogger: WindowInputDelegate {
    let log: Log
    let takes: Bool

    init(log: Log, takes: Bool) {
        self.log = log
        self.takes = takes
    }

    func windowTouchDown(id: Int, at point: Point) -> Bool {
        log("down \(id) \(Int(point.x)),\(Int(point.y))")
        return takes
    }

    func windowTouchUp(id: Int, at point: Point) -> Bool {
        log("up \(id) \(Int(point.x)),\(Int(point.y))")
        return takes
    }

    func windowMouseMoved(to point: Point) -> Bool {
        log("moved \(Int(point.x)),\(Int(point.y))")
        return takes
    }

    func windowScroll(dx: Double, dy: Double, at point: Point) -> Bool {
        log("scroll \(Int(dy)) at \(Int(point.x)),\(Int(point.y))")
        return takes
    }
}

/// Wants only the left 50 points, and takes every touch it is offered.
@MainActor
final class LeftEdgeDelegate: WindowInputDelegate {
    let log: Log

    init(log: Log) {
        self.log = log
    }

    func windowWantsInput(at point: Point) -> Bool {
        point.x < 50
    }

    func windowTouchDown(id: Int, at point: Point) -> Bool {
        log("down \(Int(point.x))")
        return true
    }
}

/// Implements nothing: every event is left to the views.
@MainActor
final class SilentDelegate: WindowInputDelegate {}

// MARK: - Tests

extension HostedViews {

    @MainActor
    @Suite
    struct WindowInputTests {

        func window<V: View>(_ view: V) -> HostingWindow<NucleantRenderNode> {
            let window = HostingWindow<NucleantRenderNode>(title: "Input", width: 200, height: 200, root: view)
            window.on_size(w: 200, h: 200)
            window.host.update()
            return window
        }

        func settle(_ window: HostingWindow<NucleantRenderNode>) async {
            try? await Task.sleep(for: .seconds(0.02))
            window.host.update()
        }

        @Test func openSpaceIsTheDelegates() async {
            let log = Log()
            let window = window(TapBesideOpenSpace(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_touch_down(id: 3, x: 150, y: 100)
            window.on_touch_moved(id: 3, x: 20, y: 100)
            window.on_touch_up(id: 3, x: 20, y: 100)
            await settle(window)
            #expect(log.take() == ["down 3 150,100", "up 3 20,100"])
        }

        @Test func aViewThatTakesPressesKeepsThem() async {
            let log = Log()
            let window = window(TapBesideOpenSpace(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 50, y: 100)
            window.on_touch_up(id: 0, x: 50, y: 100)
            await settle(window)
            #expect(log.take() == ["tap"])
        }

        @Test func whatIsDrawnOnTopKeepsItsPresses() async {
            let log = Log()
            let window = window(TapOnTop(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 100, y: 100)
            window.on_touch_up(id: 0, x: 100, y: 100)
            await settle(window)
            #expect(log.take() == ["on top"])
            window.on_touch_down(id: 1, x: 20, y: 100)
            window.on_touch_up(id: 1, x: 20, y: 100)
            await settle(window)
            #expect(log.take() == ["down 1 20,100", "up 1 20,100"])
        }

        @Test func aPressTheDelegateTakesTakesTheKeysFromTheViews() async {
            let log = Log()
            let window = window(FocusableBesideOpenSpace(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 50, y: 100)
            window.on_touch_up(id: 0, x: 50, y: 100)
            await settle(window)
            #expect(log.take() == ["focus true"])
            #expect(window.host.hasFocusedView)
            window.on_touch_down(id: 0, x: 150, y: 100)
            #expect(log.take() == ["down 0 150,100", "focus false"])
            #expect(!window.host.hasFocusedView)
        }

        @Test func onlyWhatTheDelegateWantsIsOfferedToIt() {
            let log = Log()
            let window = window(TapOnTop(log: log))
            let delegate = LeftEdgeDelegate(log: log)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 150, y: 100)
            window.on_touch_up(id: 0, x: 150, y: 100)
            window.on_touch_down(id: 1, x: 20, y: 100)
            #expect(log.take() == ["down 20"])
        }

        @Test func whatTheDelegateLeavesGoesToTheViews() async {
            let log = Log()
            let window = window(TapOnTop(log: log))
            let delegate = InputLogger(log: log, takes: false)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 20, y: 100)
            window.on_touch_up(id: 0, x: 20, y: 100)
            await settle(window)
            // Offered the press, it declined: the release is the views' too.
            #expect(log.take() == ["down 0 20,100"])
        }

        @Test func aDelegateImplementingNothingLeavesEverythingToTheViews() async {
            let log = Log()
            let window = window(TapBesideOpenSpace(log: log))
            let delegate = SilentDelegate()
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 50, y: 100)
            window.on_touch_up(id: 0, x: 50, y: 100)
            await settle(window)
            #expect(log.take() == ["tap"])
        }

        @Test func withoutADelegateTheViewsHaveEverything() async {
            let log = Log()
            let window = window(TapBesideOpenSpace(log: log))
            window.on_touch_down(id: 0, x: 50, y: 100)
            window.on_touch_up(id: 0, x: 50, y: 100)
            await settle(window)
            #expect(log.take() == ["tap"])
        }

        @Test func theWheelOverAViewThatTakesThePointerIsTheViews() {
            let log = Log()
            let window = window(TapBesideOpenSpace(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_mouse_moved(x: 50, y: 100)
            window.on_scroll(dx: 0, dy: 5)
            #expect(log.take() == [])
        }

        @Test func aScrollIsWhereTheMouseLastMoved() {
            let log = Log()
            let window = window(Color.red)
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_mouse_moved(x: 30, y: 100)
            window.on_scroll(dx: 0, dy: 5)
            #expect(log.take() == ["moved 30,100", "scroll 5 at 30,100"])
        }

        @Test func theDelegateIsNotKeptAlive() {
            let window = window(Color.red)
            var delegate: SilentDelegate? = SilentDelegate()
            window.input.delegate = delegate
            #expect(window.input.delegate != nil)
            delegate = nil
            #expect(window.input.delegate == nil)
        }

        @Test func theWindowsViewsFindItsInputInTheEnvironment() {
            let box = InputBox()
            let window = window(ReadsWindowInput(box: box))
            #expect(box.input === window.input)
        }

        @Test func aTreeHostedWithoutAWindowHasNone() {
            let box = InputBox()
            box.input = WindowInput()
            _ = Harness(ReadsWindowInput(box: box))
            #expect(box.input == nil)
        }
    }
}
