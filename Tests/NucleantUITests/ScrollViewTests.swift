//
//  ScrollViewTests.swift
//  NucleantUITests
//
//  A hosted `ScrollView` under a finger and a wheel: pulled past an edge,
//  flung, caught, bounced off the end, and nested in another. These run in
//  real time — a flick's speed comes from moves 10 ms apart — so what they
//  check is a margin, not an exact frame; the motions themselves are tested
//  at chosen times in ScrollPhysicsTests and ScrollerTests.
//

import Foundation
import Testing
@testable import NucleantUI

@View
struct ProbedRows {
    let probe: ScrollProbe
    let height: Double

    var body: some View {
        let _ = probe.builds += 1
        VStack(spacing: 0) {
            Color.red.frame(height: height / 2)
            Color.blue.frame(height: height / 2)
        }
        .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
    }
}

@View
struct ProbedScroll {
    let probe: ScrollProbe
    let height: Double

    var body: some View {
        ScrollView {
            ProbedRows(probe: probe, height: height)
        }
    }
}

@View
struct ProbedScrollWithButton {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { probe.taps += 1 } label: {
                    Color.gray.frame(width: 200, height: 3000)
                }
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
    }
}

@View
struct NestedScrolls {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    Color.green.frame(width: 1000, height: 100)
                        .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView(axis: .horizontal)).minX } action: { probe.leading = $0 }
                }
                .frame(height: 100)
                Color.blue.frame(height: 2000)
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView(axis: .vertical)).minY } action: { probe.top = $0 }
        }
    }
}

/// A sideways shelf of 100-tall cards in a page that scrolls down, with
/// `margin` above and below its cards and, when given, a `height` of its
/// own; a marker under it reports where it starts.
@View
struct ShelfInPage {
    let probe: ScrollProbe
    let margin: Double
    let height: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            Color.green.frame(width: 100, height: 100)
                        }
                    }
                }
                .contentMargins(.vertical, margin)
                .frame(height: height)
                Color.blue.frame(height: 50)
                    .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView(axis: .vertical)).minY } action: { probe.top = $0 }
            }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollViews {

        @Test(arguments: [(0.0, 100.0), (10, 120)])
        func offeredNoHeightASidewaysScrollViewIsAsTallAsItsContent(margin: Double, top: Double) {
            let probe = ScrollProbe()
            _ = Harness(ShelfInPage(probe: probe, margin: margin, height: nil))
            #expect(probe.top == top)
        }

        @Test func offeredAHeightItTakesIt() {
            let probe = ScrollProbe()
            _ = Harness(ShelfInPage(probe: probe, margin: 0, height: 160))
            #expect(probe.top == 160)
        }

        @Test func pulledPastTheTopItFollowsByTheRubberBandAndSpringsBack() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScroll(probe: probe, height: 3000))
            harness.host.scrollsOnDrag = true

            harness.host.pointerDown(at: Point(x: 100, y: 50))
            harness.host.pointerMoved(to: Point(x: 100, y: 100))
            harness.host.pointerMoved(to: Point(x: 100, y: 150))
            harness.host.update()
            #expect(abs(probe.top - 43.14) < 0.05, "100 points down from the top shows 43 of them")

            harness.host.pointerUp(at: Point(x: 100, y: 150))
            var shown: [Double] = []
            for _ in 0..<60 {
                await harness.frames(1)
                shown.append(probe.top)
            }
            #expect(zip(shown.dropFirst(), shown).allSatisfy { $0 <= $1 + 0.001 }, "back towards the top every frame")
            #expect(shown.allSatisfy { $0 >= 0 }, "never through the top")
            #expect(probe.top == 0)
        }

        @Test func flungItCarriesOnAfterTheFingerLiftsAndBuildsNothing() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScroll(probe: probe, height: 3000))
            harness.host.scrollsOnDrag = true
            let builds = probe.builds

            await harness.flick(from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            harness.host.update()
            let released = probe.top
            #expect(released <= -90)

            await harness.frames(15)
            #expect(probe.top < released - 100, "upward at 1500 pt/s: well on past where the finger left it")
            #expect(probe.builds == builds, "scrolling places the content again and builds nothing")
        }

        @Test func aFingerOnAMovingScrollViewStopsItAndTapsNothing() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScrollWithButton(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.flick(from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            await harness.frames(5)

            harness.host.pointerDown(at: center)
            harness.host.update()
            let caught = probe.top
            await harness.frames(5)
            #expect(probe.top == caught)

            harness.host.pointerUp(at: center)
            await harness.frames(3)
            #expect(probe.taps == 0, "the press only stopped the scroll")
            #expect(probe.top == caught)

            await harness.tap(center)
            #expect(probe.taps == 1, "a tap on a scroll view at rest is a tap")
        }

        @Test func flungIntoTheEndItBouncesAndComesToRestThere() async {
            let probe = ScrollProbe()
            // 400 tall in 200: rests between 0 and 200.
            let harness = Harness(ProbedScroll(probe: probe, height: 400))
            harness.host.scrollsOnDrag = true

            await harness.flick(from: Point(x: 100, y: 180), step: Point(x: 0, y: -20), count: 6)
            var furthest = 0.0
            for _ in 0..<90 {
                await harness.frames(1)
                furthest = min(furthest, probe.top)
            }
            #expect(furthest < -205, "past the end")
            #expect(probe.top == -200, "and back to rest on it")
        }

        @Test func aWheelMovesItInsideItsEndsOnly() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScroll(probe: probe, height: 400))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: 120)
            harness.host.update()
            #expect(probe.top == 0)

            harness.host.scroll(dx: 0, dy: -150)
            harness.host.update()
            #expect(probe.top == -150)

            harness.host.scroll(dx: 0, dy: -150)
            harness.host.update()
            #expect(probe.top == -200)
        }

        @Test func aMoveGoesToTheNestedScrollViewThatScrollsThatWay() async {
            let probe = ScrollProbe()
            let harness = Harness(NestedScrolls(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.drag(from: Point(x: 100, y: 60), through: [Point(x: 102, y: 30), Point(x: 104, y: 0)])
            #expect(abs(probe.top + 60) < 0.001, "up, starting on the sideways strip: the page scrolls")
            #expect(probe.leading == 0)

            await harness.frames(40)
            await harness.drag(from: Point(x: 150, y: 20), through: [Point(x: 120, y: 21), Point(x: 90, y: 22)])
            #expect(abs(probe.leading + 60) < 0.001, "sideways on the strip: the strip scrolls")

            harness.host.pointerMoved(to: Point(x: 100, y: 20))
            harness.host.scroll(dx: 0, dy: -30)
            harness.host.update()
            #expect(abs(probe.top + 90) < 0.001, "the wheel the same way")
        }
    }
}
