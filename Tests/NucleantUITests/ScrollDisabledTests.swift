//
//  ScrollDisabledTests.swift
//  NucleantUITests
//
//  `.scrollDisabled`: the environment value, and hosted scroll views that a
//  finger and a wheel no longer move — handing them to the one around —
//  while the app still can, and a drag let go of when it is disabled.
//

import Foundation
import Observation
import Testing
@testable import NucleantUI

/// Whether scrolling is enabled where a view is placed.
@MainActor
final class EnabledProbe {
    var isScrollEnabled: Bool?
}

@View
struct ScrollEnabledReader {
    let probe: EnabledProbe
    @Environment(\.isScrollEnabled) private var isScrollEnabled

    var body: some View {
        let _ = probe.isScrollEnabled = isScrollEnabled
        Color.clear
    }
}

/// A long scroll view, disabled or not.
@View
struct DisabledScroll {
    let probe: ScrollProbe
    let disabled: Bool

    var body: some View {
        ScrollView {
            ProbedRows(probe: probe, height: 3000)
        }
        .scrollDisabled(disabled)
    }
}

/// A disabled scroll view at the top of a long one: the long one's content
/// reported.
@View
struct DisabledInsideScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView {
                    Color.green.frame(height: 1000)
                }
                .frame(height: 100)
                .scrollDisabled(true)
                Color.blue.frame(height: 2000)
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
    }
}

/// A scroll view, disabled or not, the app scrolls through a reader.
@View
struct DisabledReaderRows {
    let probe: ReaderProbe
    let disabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            let _ = probe.proxy = proxy
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<50, id: \.self) { _ in
                        Color.blue.frame(height: 40)
                    }
                }
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
            }
            .scrollDisabled(disabled)
        }
    }
}

/// Whether the switchable scroll view is disabled.
@MainActor
@Observable
final class ScrollSwitch {
    var disabled = false
}

@View
struct SwitchableScroll {
    let probe: ScrollProbe
    let toggle: ScrollSwitch

    var body: some View {
        ScrollView {
            ProbedRows(probe: probe, height: 3000)
        }
        .scrollDisabled(toggle.disabled)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollDisabled {

        @Test func scrollingIsEnabledUntilDisabled() {
            let probe = EnabledProbe()
            _ = Harness(ScrollEnabledReader(probe: probe))
            #expect(probe.isScrollEnabled == true)

            _ = Harness(ScrollEnabledReader(probe: probe).scrollDisabled(true))
            #expect(probe.isScrollEnabled == false)
        }

        @Test func falseInsideADisabledViewDoesNotEnableItAgain() {
            let probe = EnabledProbe()
            _ = Harness(ScrollEnabledReader(probe: probe).scrollDisabled(false).scrollDisabled(true))
            #expect(probe.isScrollEnabled == false)

            _ = Harness(ScrollEnabledReader(probe: probe).scrollDisabled(false))
            #expect(probe.isScrollEnabled == true)
        }

        @Test(arguments: [(false, -100.0), (true, 0)])
        func aDisabledScrollViewDoesNotFollowAFinger(disabled: Bool, top: Double) async {
            let probe = ScrollProbe()
            let harness = Harness(DisabledScroll(probe: probe, disabled: disabled))
            harness.host.scrollsOnDrag = true

            await harness.drag(from: Point(x: 100, y: 150), through: [Point(x: 100, y: 100), Point(x: 100, y: 50)])
            #expect(abs(probe.top - top) < 0.001)
        }

        @Test(arguments: [(false, -100.0), (true, 0)])
        func norAWheel(disabled: Bool, top: Double) {
            let probe = ScrollProbe()
            let harness = Harness(DisabledScroll(probe: probe, disabled: disabled))

            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -100)
            harness.host.update()
            #expect(abs(probe.top - top) < 0.001)
        }

        @Test func aFingerOrAWheelOnADisabledScrollViewMovesTheOneAroundIt() async {
            let probe = ScrollProbe()
            let harness = Harness(DisabledInsideScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.drag(from: Point(x: 100, y: 80), through: [Point(x: 100, y: 50), Point(x: 100, y: 20)])
            #expect(abs(probe.top + 60) < 0.001)

            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            harness.host.scroll(dx: 0, dy: -30)
            harness.host.update()
            #expect(abs(probe.top + 90) < 0.001)
        }

        @Test(arguments: [false, true])
        func theAppStillScrollsADisabledScrollView(disabled: Bool) async throws {
            let probe = ReaderProbe()
            let harness = Harness(DisabledReaderRows(probe: probe, disabled: disabled))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo(10, anchor: .top)
            await harness.frames(2)
            #expect(probe.top == -400)
        }

        @Test func aDragUnderWayIsLetGoOfWhenItsScrollViewIsDisabled() async {
            let probe = ScrollProbe()
            let toggle = ScrollSwitch()
            let harness = Harness(SwitchableScroll(probe: probe, toggle: toggle))
            harness.host.scrollsOnDrag = true

            harness.host.pointerDown(at: Point(x: 100, y: 150))
            harness.host.pointerMoved(to: Point(x: 100, y: 100))
            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            harness.host.update()
            #expect(abs(probe.top + 100) < 0.001)

            toggle.disabled = true
            harness.host.update()
            harness.host.pointerMoved(to: Point(x: 100, y: 0))
            await harness.frames(2)
            #expect(abs(probe.top + 100) < 0.001, "the finger no longer moves it")

            harness.host.pointerUp(at: Point(x: 100, y: 0))
            await harness.frames(2)
            #expect(abs(probe.top + 100) < 0.001)
        }
    }
}
