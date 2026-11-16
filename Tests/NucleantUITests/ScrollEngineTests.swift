//
//  ScrollEngineTests.swift
//  NucleantUITests
//
//  How a `ScrollView` moves: the motions on their own, then a hosted scroll
//  view dragged by a finger, flung, caught, bounced, and turned by a wheel.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct ScrollPhysicsTests {

    @Test func theRubberBandFollowsByLessAndLessAndIsUndoneExactly() {
        let shown = ScrollPhysics.rubberBand(100, dimension: 200)
        #expect(abs(shown - 43.14) < 0.01)
        #expect(ScrollPhysics.rubberBand(-100, dimension: 200) == -shown)
        #expect(ScrollPhysics.rubberBand(400, dimension: 200) < 200 * 0.55)
        for dragged in [1.0, 30, 150, 900] {
            let banded = ScrollPhysics.rubberBand(dragged, dimension: 200)
            #expect(banded < dragged)
            #expect(abs(ScrollPhysics.dragDistance(showing: banded, dimension: 200) - dragged) < 1e-6)
        }
    }

    @Test func letGoInsideItSlowsDownToWhereItsSpeedCarriesIt() {
        var motion = ScrollAxisMotion.released(at: 0, velocity: 1000, bounds: 0...10_000, time: 0, bounces: true)!
        var last = 0.0
        var time = 0.0
        while true {
            time += 1.0 / 60
            let sample = motion.sample(at: time, bounds: 0...10_000)
            #expect(sample.position >= last)
            last = sample.position
            if sample.isFinished { break }
            #expect(time < 10)
        }
        #expect(abs(last - 1000 / ScrollPhysics.decay) < 0.5)
        #expect(abs(1000 / ScrollPhysics.decay - 499.5) < 0.1)
    }

    @Test func slowingIntoAnEdgeItRunsPastAndComesBackToRestOnIt() {
        var motion = ScrollAxisMotion.released(at: 50, velocity: 2000, bounds: 0...100, time: 0, bounces: true)!
        var furthest = 0.0
        var final = 0.0
        for frame in 1...120 {
            let sample = motion.sample(at: Double(frame) / 60, bounds: 0...100)
            furthest = max(furthest, sample.position)
            final = sample.position
            if sample.isFinished { break }
        }
        #expect(furthest > 120)
        #expect(final == 100)
    }

    @Test func withoutBouncingItStopsDeadAtTheEdge() {
        var motion = ScrollAxisMotion.released(at: 50, velocity: 2000, bounds: 0...100, time: 0, bounces: false)!
        var finished = false
        for frame in 1...120 {
            let sample = motion.sample(at: Double(frame) / 60, bounds: 0...100)
            #expect(sample.position <= 100)
            if sample.isFinished {
                #expect(sample.position == 100)
                finished = true
                break
            }
        }
        #expect(finished)
    }

    @Test func letGoPastAnEdgeAtRestItSpringsBackWithoutSwingingThrough() {
        var motion = ScrollAxisMotion.released(at: -50, velocity: 0, bounds: 0...100, time: 0, bounces: true)!
        var last = -50.0
        for frame in 1...90 {
            let sample = motion.sample(at: Double(frame) / 60, bounds: 0...100)
            #expect(sample.position >= last)
            #expect(sample.position <= 0)
            last = sample.position
            if sample.isFinished { break }
        }
        #expect(last == 0)
    }

    @Test func flungBackInFromPastAnEdgeItSlowsDownInsideInsteadOfSpringing() {
        let motion = ScrollAxisMotion.released(at: -30, velocity: 3000, bounds: 0...10_000, time: 0, bounces: true)
        #expect(motion?.kind == .decelerating(position: -30, velocity: 3000))
    }

    @Test func settlingOnATargetFastDoesNotRunPastIt() {
        var motion = ScrollAxisMotion.settling(from: 0, velocity: 6000, to: 300, time: 0, bounces: true)!
        for frame in 1...90 {
            let sample = motion.sample(at: Double(frame) / 60, bounds: 0...1000)
            #expect(sample.position <= 300.0001)
            if sample.isFinished {
                #expect(sample.position == 300)
                return
            }
        }
        Issue.record("never arrived")
    }

    @Test func aFingerThatStoppedBeforeLiftingFlingsNothing() {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 1.000)
        tracker.add(Point(x: 0, y: 20), at: 1.010)
        tracker.add(Point(x: 0, y: 40), at: 1.020)
        #expect(abs(tracker.velocity(at: 1.021).y - 2000) < 1)
        #expect(tracker.velocity(at: 1.1) == .zero)

        // Moves with no time between them tell no speed.
        var together = ScrollVelocityTracker()
        together.add(Point(x: 0, y: 0), at: 2.0)
        together.add(Point(x: 0, y: 100), at: 2.0001)
        #expect(together.velocity(at: 2.0001) == .zero)
    }
}

// MARK: - Hosted

/// Where the content of a scroll view is, and how often it was built.
@MainActor
final class ScrollProbe {
    /// The top of the content in the scroll view's space: minus the offset.
    var top = 0.0
    var leading = 0.0
    var builds = 0
    var taps = 0
}

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

extension HostedViews {
    @MainActor
    @Suite struct ScrollEngine {

        /// A frame's worth of time, and the frame.
        private func frames(_ count: Int, _ harness: Harness) async {
            for _ in 0..<count { await harness.settle(1.0 / 60) }
        }

        /// A finger from `from` moving by `step` `count` times, 10 ms apart —
        /// 100 events a second, so it is let go of at `step` per 10 ms.
        private func flick(_ harness: Harness, from: Point, step: Point, count: Int) async {
            harness.host.pointerDown(at: from)
            var point = from
            for _ in 0..<count {
                try? await Task.sleep(for: .milliseconds(10))
                point += step
                harness.host.pointerMoved(to: point)
            }
            harness.host.pointerUp(at: point)
        }

        @Test func pulledPastTheTopItFollowsByTheRubberBandAndSpringsBack() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScroll(probe: probe, height: 3000))
            harness.host.scrollsOnDrag = true

            harness.host.pointerDown(at: Point(x: 100, y: 50))
            harness.host.pointerMoved(to: Point(x: 100, y: 100))
            harness.host.pointerMoved(to: Point(x: 100, y: 150))
            harness.host.update()
            // 100 points down from the top shows 43 of them.
            #expect(abs(probe.top - 43.14) < 0.05)

            harness.host.pointerUp(at: Point(x: 100, y: 150))
            var last = probe.top
            for _ in 0..<60 {
                await harness.settle(1.0 / 60)
                #expect(probe.top <= last + 0.001)
                #expect(probe.top >= 0)
                last = probe.top
            }
            #expect(probe.top == 0)
        }

        @Test func flungItCarriesOnAfterTheFingerLiftsAndBuildsNothing() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScroll(probe: probe, height: 3000))
            harness.host.scrollsOnDrag = true
            let builds = probe.builds

            await flick(harness, from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            harness.host.update()
            let released = probe.top
            #expect(released < -60)

            await frames(15, harness)
            // Upward at 1500 pt/s: well on past where the finger left it.
            #expect(probe.top < released - 100)
            #expect(probe.builds == builds)
        }

        @Test func aFingerOnAMovingScrollViewStopsItAndTapsNothing() async {
            let probe = ScrollProbe()
            let harness = Harness(ProbedScrollWithButton(probe: probe))
            harness.host.scrollsOnDrag = true

            await flick(harness, from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            await frames(5, harness)

            harness.host.pointerDown(at: center)
            harness.host.update()
            let caught = probe.top
            await frames(5, harness)
            #expect(probe.top == caught)

            harness.host.pointerUp(at: center)
            await frames(3, harness)
            #expect(probe.taps == 0)
            #expect(probe.top == caught)

            // Still, a tap is a tap.
            await harness.tap(center)
            #expect(probe.taps == 1)
        }

        @Test func flungIntoTheEndItBouncesAndComesToRestThere() async {
            let probe = ScrollProbe()
            // 400 tall in 200: rests between 0 and 200.
            let harness = Harness(ProbedScroll(probe: probe, height: 400))
            harness.host.scrollsOnDrag = true

            await flick(harness, from: Point(x: 100, y: 180), step: Point(x: 0, y: -20), count: 6)
            var furthest = 0.0
            for _ in 0..<90 {
                await harness.settle(1.0 / 60)
                furthest = min(furthest, probe.top)
            }
            #expect(furthest < -205)
            #expect(probe.top == -200)
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

            // Up, starting on the sideways strip: the page scrolls.
            await harness.drag(from: Point(x: 100, y: 60), through: [Point(x: 102, y: 30), Point(x: 104, y: 0)])
            #expect(abs(probe.top + 60) < 0.001)
            #expect(probe.leading == 0)

            await frames(40, harness)

            // Sideways on the strip: the strip.
            await harness.drag(from: Point(x: 150, y: 20), through: [Point(x: 120, y: 21), Point(x: 90, y: 22)])
            #expect(abs(probe.leading + 60) < 0.001)

            // The wheel the same way.
            harness.host.pointerMoved(to: Point(x: 100, y: 20))
            harness.host.scroll(dx: 0, dy: -30)
            harness.host.update()
            #expect(abs(probe.top + 90) < 0.001)
        }
    }
}
