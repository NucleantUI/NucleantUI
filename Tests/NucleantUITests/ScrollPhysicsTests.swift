//
//  ScrollPhysicsTests.swift
//  NucleantUITests
//
//  The motions a scroll view makes on its own, one axis at a time, sampled
//  at chosen times: the rubber band, slowing down, bouncing off an edge,
//  settling on a target, and the speed a finger lets go at.
//

import Foundation
import Testing
@testable import NucleantUI

/// `motion` sampled every sixtieth of a second until it finishes, or for at
/// most `limit` seconds: the positions on the way and where it ended.
private func run(
    _ motion: ScrollAxisMotion,
    bounds: ClosedRange<Double>,
    limit: Double = 10
) -> (positions: [Double], final: Double, finished: Bool) {
    var motion = motion
    var positions: [Double] = []
    var time = 0.0
    while time < limit {
        time += 1.0 / 60
        let sample = motion.sample(at: time, bounds: bounds)
        positions.append(sample.position)
        if sample.isFinished { return (positions, sample.position, true) }
    }
    return (positions, positions.last ?? .nan, false)
}

struct RubberBandTests {

    @Test func aHundredPointsPastTheEdgeOfTwoHundredShowsUIScrollViewsFortyThree() {
        let shown = RubberBand(dimension: 200).shown(dragged: 100)
        #expect(abs(shown - 43.14) < 0.01, "UIScrollView's rubber band: (1 − 1/(100·0.55/200 + 1))·200")
    }

    @Test(arguments: [0.5, 30, 100, 150, 900, 50_000])
    func theContentFollowsByLessThanTheFingerAndNeverAsFarAsTheViewport(dragged: Double) {
        let shown = RubberBand(dimension: 200).shown(dragged: dragged)
        #expect(shown > 0)
        #expect(shown < dragged)
        #expect(shown < 200)
    }

    @Test(arguments: [0.5, 30, 100, 150, 900])
    func pastEitherEdgeItBandsTheSame(dragged: Double) {
        #expect(RubberBand(dimension: 200).shown(dragged: -dragged) == -RubberBand(dimension: 200).shown(dragged: dragged))
    }

    @Test(arguments: [-900.0, -30, 0.5, 30, 100, 150, 900])
    func whatTheBandShowsIsUndoneToWhatWasDragged(dragged: Double) {
        let shown = RubberBand(dimension: 200).shown(dragged: dragged)
        let undone = RubberBand(dimension: 200).dragged(shown: shown)
        #expect(abs(undone - dragged) < 1e-6)
    }

    @Test func aViewportWithNoLengthBandsNothing() {
        #expect(RubberBand(dimension: 0).shown(dragged: 100) == 0)
        #expect(RubberBand(dimension: 0).dragged(shown: 40) == 0)
    }

    @Test func showingAsFarAsTheViewportUndoesToAFiniteDrag() {
        let dragged = RubberBand(dimension: 200).dragged(shown: 250)
        #expect(dragged.isFinite)
        #expect(dragged > 0)
    }
}

struct ScrollAxisMotionTests {

    @Test func theDecayIsUIScrollViewsNormalRate() {
        #expect(abs(ScrollPhysics.decay - 2.002) < 0.001, "the speed kept is 0.998 each millisecond")
    }

    @Test(arguments: [-3000.0, -500, 0, 500, 3000])
    func flungItComesToRestWhereItsSpeedCarriesIt(velocity: Double) {
        #expect(ScrollAxisMotion.projectedEnd(from: 1000, velocity: velocity) == 1000 + velocity / ScrollPhysics.decay)
    }

    @Test(arguments: [0.0, 0.4, -0.4])
    func letGoInsideAtNoSpeedItDoesNotMove(velocity: Double) {
        #expect(ScrollAxisMotion.released(at: 50, velocity: velocity, bounds: 0...100, time: 0, bounces: true) == nil)
    }

    @Test(arguments: [800.0, -800, 2500, -2500])
    func letGoInsideItSlowsDownToItsProjectedEnd(velocity: Double) throws {
        let motion = try #require(ScrollAxisMotion.released(at: 5000, velocity: velocity, bounds: 0...10_000, time: 0, bounces: true))
        let result = run(motion, bounds: 0...10_000)
        #expect(result.finished)
        #expect(abs(result.final - ScrollAxisMotion.projectedEnd(from: 5000, velocity: velocity)) < 0.5)
        // Always the same way, and slower each frame — until the last, where
        // it is put on its projected end: what is left at half a point a
        // second, and that frame's own way at it.
        let steps = zip(result.positions.dropFirst(), result.positions).map { $0 - $1 }
        #expect(steps.allSatisfy { $0 * velocity >= 0 })
        let slowing = steps.dropLast()
        #expect(zip(slowing.dropFirst(), slowing).allSatisfy { abs($0) <= abs($1) + 1e-9 })
        let lastJump = ScrollPhysics.restingSpeed / ScrollPhysics.decay + ScrollPhysics.restingSpeed / 60
        #expect(abs(steps.last ?? 0) <= lastJump + 1e-9)
    }

    @Test(arguments: [(50.0, 2000.0, 100.0), (50, -2000, 0)])
    func slowingIntoAnEdgeItRunsPastAndComesBackToRestOnIt(start: Double, velocity: Double, edge: Double) throws {
        let motion = try #require(ScrollAxisMotion.released(at: start, velocity: velocity, bounds: 0...100, time: 0, bounces: true))
        let result = run(motion, bounds: 0...100)
        let furthestPast = result.positions.map { velocity > 0 ? $0 - edge : edge - $0 }.max() ?? 0
        #expect(furthestPast > 20, "it bounces past the edge")
        #expect(result.finished)
        #expect(result.final == edge)
    }

    @Test(arguments: [(50.0, 2000.0, 100.0), (50, -2000, 0)])
    func withoutBouncingItStopsDeadAtTheEdge(start: Double, velocity: Double, edge: Double) throws {
        let motion = try #require(ScrollAxisMotion.released(at: start, velocity: velocity, bounds: 0...100, time: 0, bounces: false))
        let result = run(motion, bounds: 0...100)
        #expect(result.positions.allSatisfy { (0...100).contains($0) })
        #expect(result.finished)
        #expect(result.final == edge)
    }

    @Test func howeverHardItIsFlungItBouncesNoFurtherThanAtTheBounceSpeedCap() throws {
        func furthest(_ velocity: Double) throws -> Double {
            let motion = try #require(ScrollAxisMotion.released(at: 99.9, velocity: velocity, bounds: 0...100, time: 0, bounces: true))
            return run(motion, bounds: 0...100).positions.max() ?? 0
        }
        let atCap = try furthest(ScrollPhysics.maximumBounceSpeed)
        let wayPast = try furthest(ScrollPhysics.maximumBounceSpeed * 3)
        #expect(abs(wayPast - atCap) < 1)
    }

    @Test(arguments: [-50.0, -200, 150, 300])
    func letGoPastAnEdgeAtRestItSpringsBackWithoutSwingingThrough(start: Double) throws {
        let edge = start < 0 ? 0.0 : 100.0
        let motion = try #require(ScrollAxisMotion.released(at: start, velocity: 0, bounds: 0...100, time: 0, bounces: true))
        let result = run(motion, bounds: 0...100)
        let distances = result.positions.map { abs($0 - edge) }
        #expect(zip(distances.dropFirst(), distances).allSatisfy { $0 <= $1 + 1e-9 }, "closer to the edge every frame")
        #expect(result.positions.allSatisfy { start < 0 ? $0 <= 0 : $0 >= 100 }, "never through the edge")
        #expect(result.final == edge)
    }

    @Test func flungBackInFromPastAnEdgeItSlowsDownInsideInsteadOfSpringing() {
        let motion = ScrollAxisMotion.released(at: -30, velocity: 3000, bounds: 0...10_000, time: 0, bounces: true)
        #expect(motion?.kind == .decelerating(position: -30, velocity: 3000))
    }

    @Test func flungFurtherOutFromPastAnEdgeItSpringsBack() {
        let motion = ScrollAxisMotion.released(at: -30, velocity: -500, bounds: 0...10_000, time: 0, bounces: true)
        guard case .settling(_, _, let target, _) = motion?.kind else {
            Issue.record("expected the settling spring, got \(String(describing: motion?.kind))")
            return
        }
        #expect(target == 0)
    }

    @Test(arguments: [0.0, 1500, 6000, 20_000])
    func settlingOnATargetItDoesNotRunPastIt(velocity: Double) throws {
        let motion = try #require(ScrollAxisMotion.settling(from: 0, velocity: velocity, to: 300, time: 0, bounces: true))
        let result = run(motion, bounds: 0...1000)
        #expect(result.positions.allSatisfy { $0 <= 300.0001 })
        #expect(result.final == 300)
    }

    @Test func alreadyOnTheTargetAndStillThereIsNothingToSettle() {
        #expect(ScrollAxisMotion.settling(from: 300, velocity: 0, to: 300, time: 0, bounces: true) == nil)
    }

    @Test func sampledBeforeItStartedItIsWhereItStarts() throws {
        var motion = try #require(ScrollAxisMotion.released(at: 50, velocity: 1000, bounds: 0...1000, time: 10, bounces: true))
        #expect(motion.sample(at: 9, bounds: 0...1000).position == 50)
    }
}

struct ScrollVelocityTrackerTests {

    @Test func aSteadyFingerIsGoingAtItsSpeed() {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 1.000)
        tracker.add(Point(x: 0, y: 20), at: 1.010)
        tracker.add(Point(x: 0, y: 40), at: 1.020)
        let velocity = tracker.velocity(at: 1.021)
        #expect(abs(velocity.y - 2000) < 1)
        #expect(velocity.x == 0)
    }

    @Test(arguments: [0.041, 0.1, 2.0])
    func aFingerThatHeldStillBeforeLiftingFlingsNothing(still: Double) {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 1.000)
        tracker.add(Point(x: 0, y: 40), at: 1.020)
        #expect(tracker.velocity(at: 1.020 + still) == .zero)
    }

    @Test func movesWithNoTimeBetweenThemTellNoSpeed() {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 2.0)
        tracker.add(Point(x: 0, y: 100), at: 2.0001)
        #expect(tracker.velocity(at: 2.0001) == .zero)
    }

    @Test func withNoMovesOrOneThereIsNoSpeed() {
        var tracker = ScrollVelocityTracker()
        #expect(tracker.velocity(at: 1) == .zero)
        tracker.add(Point(x: 10, y: 10), at: 1)
        #expect(tracker.velocity(at: 1) == .zero)
    }

    @Test func onlyTheLastTenthOfASecondCounts() {
        var tracker = ScrollVelocityTracker()
        // Slow for a long while, then fast for the last 50 ms.
        tracker.add(Point(x: 0, y: 0), at: 0.0)
        tracker.add(Point(x: 0, y: 10), at: 0.5)
        tracker.add(Point(x: 0, y: 20), at: 0.55)
        tracker.add(Point(x: 0, y: 120), at: 0.6)
        let velocity = tracker.velocity(at: 0.6)
        #expect(abs(velocity.y - 1100) < 1, "(120 − 10) over the 100 ms before the last move")
    }

    @Test func aMoveStampedBeforeTheLastIsIgnored() {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 1.00)
        tracker.add(Point(x: 0, y: 20), at: 1.01)
        tracker.add(Point(x: 0, y: 900), at: 1.005)
        #expect(abs(tracker.velocity(at: 1.01).y - 2000) < 1)
    }

    @Test func resetForgetsEveryMove() {
        var tracker = ScrollVelocityTracker()
        tracker.add(Point(x: 0, y: 0), at: 1.00)
        tracker.add(Point(x: 0, y: 20), at: 1.01)
        tracker.reset()
        #expect(tracker.velocity(at: 1.01) == .zero)
    }
}
