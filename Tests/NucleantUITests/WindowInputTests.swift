//
//  WindowInputTests.swift
//  NucleantUITests
//
//  A window's `WindowInputDelegate`: it hears the window's events before
//  the views, keeps from them what it takes, and leaves them the rest; the
//  window's views find it through `\.windowInput`.
//
//  The events go in at y = 100 of a 200-point-high window, where AppKit's
//  bottom-up y and the views' top-down one agree.
//

import Foundation
import Testing
@testable import NucleantUI

// MARK: - Views and delegates

@View
struct TapTarget {
    let log: Log

    var body: some View {
        Color.red.onTapGesture { log("tap") }
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

        @Test func whatTheDelegateTakesNeverReachesTheViews() async {
            let log = Log()
            let window = window(TapTarget(log: log))
            let delegate = InputLogger(log: log, takes: true)
            window.input.delegate = delegate
            window.on_touch_down(id: 3, x: 100, y: 100)
            window.on_touch_up(id: 3, x: 100, y: 100)
            await settle(window)
            #expect(log.take() == ["down 3 100,100", "up 3 100,100"])
        }

        @Test func whatTheDelegateLeavesGoesToTheViews() async {
            let log = Log()
            let window = window(TapTarget(log: log))
            let delegate = InputLogger(log: log, takes: false)
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 100, y: 100)
            window.on_touch_up(id: 0, x: 100, y: 100)
            await settle(window)
            #expect(log.take() == ["down 0 100,100", "up 0 100,100", "tap"])
        }

        @Test func aDelegateImplementingNothingLeavesEverythingToTheViews() async {
            let log = Log()
            let window = window(TapTarget(log: log))
            let delegate = SilentDelegate()
            window.input.delegate = delegate
            window.on_touch_down(id: 0, x: 100, y: 100)
            window.on_touch_up(id: 0, x: 100, y: 100)
            await settle(window)
            #expect(log.take() == ["tap"])
        }

        @Test func withoutADelegateTheViewsHaveEverything() async {
            let log = Log()
            let window = window(TapTarget(log: log))
            window.on_touch_down(id: 0, x: 100, y: 100)
            window.on_touch_up(id: 0, x: 100, y: 100)
            await settle(window)
            #expect(log.take() == ["tap"])
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
