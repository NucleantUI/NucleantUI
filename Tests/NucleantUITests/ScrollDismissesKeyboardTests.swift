//
//  ScrollDismissesKeyboardTests.swift
//  NucleantUITests
//
//  `.scrollDismissesKeyboard`: when a scroll view's engine says a finger
//  puts the keyboard away, and a hosted text field over rows losing the
//  keys to a finger scrolling them — or keeping them — where the platform
//  shows a keyboard on screen.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct ScrollKeyboardDismissalTests {

    /// A scroller over long content, `mode`, halfway down it.
    private func scroller(_ mode: ScrollDismissesKeyboardMode, axes: Axis.Set = .vertical) -> Scroller {
        let scroller = Scroller()
        scroller.axes = axes
        scroller.keyboardDismissal = mode
        _ = scroller.place(viewport: Size(width: 200, height: 200), contentSize: Size(width: 2000, height: 2000), at: 0)
        scroller.scroll(to: Point(x: 500, y: 500), animation: nil, at: 0)
        return scroller
    }

    /// A finger moving by `step` every 10 ms five times, lifted at the last.
    private func flick(_ scroller: Scroller, step: Point) {
        scroller.beginDrag(at: 0)
        for index in 1...5 {
            scroller.drag(by: step, at: Double(index) * 0.01)
        }
        scroller.endDrag(at: 0.05)
    }

    @Test(arguments: [
        (ScrollDismissesKeyboardMode.automatic, true),
        (.immediately, true),
        (.interactively, false),
        (.never, false),
    ])
    func asTheDragBeginsTheKeyboardGoesAutomaticallyOrImmediately(mode: ScrollDismissesKeyboardMode, dismisses: Bool) {
        let scroller = scroller(mode)
        scroller.beginDrag(at: 0)
        #expect(scroller.dismissesKeyboard(onRelease: false) == dismisses)
    }

    @Test(arguments: [ScrollDismissesKeyboardMode.automatic, .immediately, .never])
    func onlyInteractivelyIsItDecidedAsTheFingerLetsGo(mode: ScrollDismissesKeyboardMode) {
        let scroller = scroller(mode)
        flick(scroller, step: Point(x: 0, y: 15))
        #expect(!scroller.dismissesKeyboard(onRelease: true))
    }

    @Test(arguments: [(15.0, true), (-15, false)])
    func interactivelyItGoesWhenTheFingerLetsGoMovingTheContentDown(step: Double, dismisses: Bool) {
        let scroller = scroller(.interactively)
        flick(scroller, step: Point(x: 0, y: step))
        #expect(scroller.dismissesKeyboard(onRelease: true) == dismisses)
    }

    @Test func aSidewaysScrollViewNeverPutsItAwayInteractively() {
        let scroller = scroller(.interactively, axes: .horizontal)
        flick(scroller, step: Point(x: 15, y: 15))
        #expect(!scroller.dismissesKeyboard(onRelease: true))
    }
}

// MARK: - Hosted

/// A text field with the keys over long rows, in a scroll view under
/// `mode`.
@View
struct FieldOverRows {
    let mode: ScrollDismissesKeyboardMode
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TextField("Search", text: $text)
                    .focused($focused)
                    .frame(height: 40)
                Color.blue.frame(height: 2000)
            }
        }
        .scrollDismissesKeyboard(mode)
        .onAppear { focused = true }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollDismissesKeyboard {

        /// A host with `FieldOverRows` under `mode`, its field focused, on
        /// a platform with an on-screen keyboard unless told otherwise.
        private func harness(_ mode: ScrollDismissesKeyboardMode, softKeyboard: Bool = true) async throws -> Harness {
            let harness = Harness(FieldOverRows(mode: mode))
            harness.host.scrollsOnDrag = true
            harness.host.hasSoftKeyboard = softKeyboard
            await harness.frames(1)
            try #require(harness.host.focusedTextInput == .singleLine)
            return harness
        }

        @Test(arguments: [ScrollDismissesKeyboardMode.automatic, .immediately])
        func aFingerScrollingTheRowsTakesTheKeysAsItBegins(mode: ScrollDismissesKeyboardMode) async throws {
            let harness = try await harness(mode)
            harness.host.pointerDown(at: Point(x: 100, y: 150))
            harness.host.pointerMoved(to: Point(x: 100, y: 120))
            harness.host.pointerMoved(to: Point(x: 100, y: 90))
            #expect(harness.host.focusedTextInput == .none)
            harness.host.pointerUp(at: Point(x: 100, y: 90))
        }

        @Test func neverItKeepsThem() async throws {
            let harness = try await harness(.never)
            await harness.drag(from: Point(x: 100, y: 150), through: [Point(x: 100, y: 120), Point(x: 100, y: 90)])
            #expect(harness.host.focusedTextInput == .singleLine)
        }

        @Test func interactivelyTheyGoWhenTheFingerLetsGoMovingTheContentDown() async throws {
            let harness = try await harness(.interactively)
            harness.host.pointerDown(at: Point(x: 100, y: 60))
            harness.host.pointerMoved(to: Point(x: 100, y: 90))
            harness.host.pointerMoved(to: Point(x: 100, y: 120))
            #expect(harness.host.focusedTextInput == .singleLine, "not while the finger is down")
            harness.host.pointerUp(at: Point(x: 100, y: 120))
            harness.host.update()
            #expect(harness.host.focusedTextInput == .singleLine, "let go with no speed")

            await harness.frames(40)
            await harness.flick(from: Point(x: 100, y: 60), step: Point(x: 0, y: 15), count: 6)
            #expect(harness.host.focusedTextInput == .none)
        }

        @Test func interactivelyReversingBeforeLettingGoKeepsThem() async throws {
            let harness = try await harness(.interactively)
            await harness.flick(from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            #expect(harness.host.focusedTextInput == .singleLine)
        }

        @Test func aPressOnTheRowsThatDoesNotScrollStillTakesThemAsItLifts() async throws {
            let harness = try await harness(.never)
            harness.host.pointerDown(at: Point(x: 100, y: 150))
            #expect(harness.host.focusedTextInput == .singleLine, "not as it goes down")
            harness.host.pointerUp(at: Point(x: 100, y: 150))
            #expect(harness.host.focusedTextInput == .none)
        }

        @Test func withoutAnOnScreenKeyboardAPressOnTheRowsTakesThemAsItGoesDownAsAnywhere() async throws {
            let harness = try await harness(.never, softKeyboard: false)
            harness.host.pointerDown(at: Point(x: 100, y: 150))
            #expect(harness.host.focusedTextInput == .none)
            harness.host.pointerUp(at: Point(x: 100, y: 150))
        }

        @Test func aWheelNeverTakesThem() async throws {
            let harness = try await harness(.immediately)
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -100)
            harness.host.update()
            #expect(harness.host.focusedTextInput == .singleLine)
        }
    }
}
