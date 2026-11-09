//
//  RetargetTests.swift
//  NucleantUITests
//
//  A value given a new target while it is still animating: under a spring
//  it keeps its velocity, under another curve the motion under way keeps
//  running beneath the new one, and in both the value does not jump. And
//  the clock of a new animation: a late first frame does not skip the
//  start of the curve. Driven with explicit times, one call per frame.
//

import Foundation
import Testing
@testable import NucleantUI

@Suite
@MainActor
struct RetargetTests {

    private let frame = 1.0 / 60

    private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
        abs(a - b) <= tolerance
    }

    /// Samples `motion` every frame from `from` up to `to`, as a host
    /// would; returns the last displacement.
    @discardableResult
    private func run<V: VectorArithmetic>(_ motion: Motion<V>, from: Double, to: Double) -> V {
        var now = from
        var last = motion.displacement(at: now).value
        while now < to - 1e-9 {
            now = min(to, now + frame)
            last = motion.displacement(at: now).value
        }
        return last
    }

    // MARK: - Springs keep their velocity

    @Test func aRetargetedSpringKeepsItsVelocity() throws {
        let spring = Animation.spring(duration: 0.5)
        // 0 → 100.
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: spring, at: 0))
        let before = run(first, from: 0, to: 0.1)
        let velocity = first.velocity(at: 0.1)
        #expect(velocity > 100)

        // 100 → 200 at 0.1 s, while still moving.
        let second = try #require(Motion<Double>.begin(offset: -100, previous: first, animation: spring, at: 0.1))
        // Where it shows: 100 + before, the same as 200 + the new displacement.
        #expect(close(200 + second.displacement(at: 0.1).value, 100 + before, 1e-9))
        // Going as fast as it was — not from rest.
        #expect(close(second.velocity(at: 0.1), velocity, 1e-6))

        let end = run(second, from: 0.1, to: 3)
        #expect(close(end, 0, 1e-9))
        #expect(second.displacement(at: 3).isFinished)
    }

    @Test func aSpringRetargetedToWhereItIsKeepsMoving() throws {
        let spring = Animation.spring(duration: 0.5)
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: spring, at: 0))
        let before = run(first, from: 0, to: 0.1)
        // The new target is exactly where the value shows, 100 + before:
        // the old target is −before from it. Carrying its velocity, the
        // value overshoots it, as a thing in motion does, instead of
        // sitting still.
        let carried = try #require(Motion<Double>.begin(offset: -before, previous: first, animation: spring, at: 0.1))
        #expect(close(carried.displacement(at: 0.1).value, 0, 1e-9))
        run(carried, from: 0.1, to: 0.2)
        #expect(carried.displacement(at: 0.2).value > 1)
    }

    @Test func aSpringStartedFromRestIsTheSameAsBefore() throws {
        // No motion under way: the curve is the spring's own, unit for unit.
        let animation = Animation.spring(duration: 0.5, bounce: 0.2)
        let motion = try #require(Motion<Double>.begin(offset: -1, previous: nil, animation: animation, at: 0))
        for step in 0...30 {
            let now = Double(step) * frame
            let expected = 1 - animation.progress(after: now).fraction
            #expect(close(-motion.displacement(at: now).value, expected, 1e-9))
        }
    }

    // MARK: - Other curves run on beneath the new one

    @Test func aRetargetedEaseTurnsWithoutAJump() throws {
        let ease = Animation.easeInOut(duration: 1)
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: ease, at: 0))
        let before = run(first, from: 0, to: 0.5)
        let velocity = first.velocity(at: 0.5)
        #expect(velocity > 50)

        let second = try #require(Motion<Double>.begin(offset: -100, previous: first, animation: ease, at: 0.5))
        #expect(close(200 + second.displacement(at: 0.5).value, 100 + before, 1e-9))
        // An ease starts flat, so the speed is the old curve's.
        #expect(close(second.velocity(at: 0.5), velocity, 1))

        // The first frame after: moving on, not restarted from rest.
        let next = second.displacement(at: 0.5 + frame).value
        #expect(next - second.displacement(at: 0.5).value > velocity * frame * 0.5)

        let end = run(second, from: 0.5, to: 1.6)
        #expect(close(end, 0, 1e-9))
        #expect(second.displacement(at: 1.6).isFinished)
    }

    @Test func vectorsRetargetComponentByComponent() throws {
        let spring = Animation.spring(duration: 0.4)
        let first = try #require(Motion<ComponentVector>.begin(
            offset: ComponentVector([-100, 50]), previous: nil, animation: spring, at: 0
        ))
        let before = run(first, from: 0, to: 0.1)
        let velocity = first.velocity(at: 0.1)
        let second = try #require(Motion<ComponentVector>.begin(
            offset: ComponentVector([-10, 0]), previous: first, animation: spring, at: 0.1
        ))
        let after = second.displacement(at: 0.1).value
        #expect(close(after[0], before[0] - 10, 1e-9))
        #expect(close(after[1], before[1], 1e-9))
        let carried = second.velocity(at: 0.1)
        #expect(close(carried[0], velocity[0], 1e-6))
        #expect(close(carried[1], velocity[1], 1e-6))
    }

    // MARK: - What merges

    @Test func aDelayedSpringLetsTheOldMotionRunThroughItsDelay() throws {
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: .easeInOut(duration: 1), at: 0))
        run(first, from: 0, to: 0.3)
        // A spring with a delay the ease didn't have: combined, not merged.
        let second = try #require(Motion<Double>.begin(
            offset: -100, previous: first, animation: .spring(duration: 0.5).delay(0.2), at: 0.3
        ))
        let start = second.displacement(at: 0.3).value
        run(second, from: 0.3, to: 0.4)
        // Still in the delay, yet moving: the ease runs on beneath it.
        #expect(second.displacement(at: 0.4).value > start + 1)
    }

    @Test func aSpringWithTheSameDelayMerges() throws {
        let spring = Animation.spring(duration: 0.5).delay(0.1)
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: spring, at: 0))
        run(first, from: 0, to: 0.3)
        let velocity = first.velocity(at: 0.3)
        let second = try #require(Motion<Double>.begin(offset: -100, previous: first, animation: spring, at: 0.3))
        let start = second.displacement(at: 0.3).value
        // Held through its own delay, as SwiftUI's merged spring is…
        run(second, from: 0.3, to: 0.39)
        #expect(second.displacement(at: 0.39).value == start)
        // …then off at the speed it had.
        #expect(close(second.velocity(at: 0.4), velocity, 1e-6))
    }

    @Test func anEndlessRepeatIsNotKeptBeneath() throws {
        let pulse = Animation.easeInOut(duration: 0.5).repeatForever()
        let first = try #require(Motion<Double>.begin(offset: -100, previous: nil, animation: pulse, at: 0))
        let before = run(first, from: 0, to: 0.7)
        let second = try #require(Motion<Double>.begin(offset: -100, previous: first, animation: pulse, at: 0.7))
        // No jump: it starts where the pulse showed it…
        #expect(close(200 + second.displacement(at: 0.7).value, 100 + before, 1e-9))
        // …and the new pulse alone drives it: one cycle there and back
        // later, it is at the new target, with no old pulse added on top.
        run(second, from: 0.7, to: 1.2)
        #expect(close(second.displacement(at: 1.2).value, 0, 1e-6))
    }

    // MARK: - Logical completion

    @Test func aSpringIsLogicallyCompleteOneResponseIn() {
        let run = AnimationRun(.spring(duration: 0.5), start: 0)
        _ = run.progress(at: 0)
        _ = run.progress(at: frame)
        #expect(!run.isLogicallyComplete(at: 0.49))
        #expect(run.isLogicallyComplete(at: 0.5))
        // Still settling.
        #expect(!run.isDone(at: 0.5))
    }

    @Test func anEaseIsLogicallyCompleteAtItsEnd() {
        let run = AnimationRun(.easeInOut(duration: 0.4), start: 0)
        _ = run.progress(at: frame)
        #expect(!run.isLogicallyComplete(at: 0.39))
        #expect(run.isLogicallyComplete(at: 0.4))
    }

    @Test func logicallyCompleteAfterSetsTheTimeAfterTheDelay() {
        let run = AnimationRun(.easeInOut(duration: 2).delay(0.5).logicallyComplete(after: 0.3), start: 0)
        _ = run.progress(at: frame)
        #expect(!run.isLogicallyComplete(at: 0.79))
        #expect(run.isLogicallyComplete(at: 0.8))
        #expect(!run.isDone(at: 0.8))
    }

    @Test func anEndlessRepeatIsLogicallyCompleteOnlyWhenTold() {
        let pulse = AnimationRun(.easeInOut(duration: 0.5).repeatForever(), start: 0)
        _ = pulse.progress(at: frame)
        #expect(!pulse.isLogicallyComplete(at: 100))
        let told = AnimationRun(.easeInOut(duration: 0.5).repeatForever().logicallyComplete(after: 1), start: 0)
        _ = told.progress(at: frame)
        #expect(told.isLogicallyComplete(at: 1))
    }

    @Test func theCompletionCriteriaChooseWhichEndIsWaitedFor() {
        let run = AnimationRun(.spring(duration: 0.5), start: 0)
        _ = run.progress(at: frame)
        let logical = AnimationCompletion(criteria: .logicallyComplete) {}
        let removed = AnimationCompletion(criteria: .removed) {}
        logical.runs = [run]
        removed.runs = [run]
        #expect(logical.isDue(at: 0.5))
        #expect(!removed.isDue(at: 0.5))
        let end = run.animation.totalDuration
        #expect(removed.isDue(at: end))
    }

    // MARK: - The clock

    @Test func aLateFirstFrameDoesNotSkipTheStart() {
        let run = AnimationRun(.linear(duration: 1), start: 0)
        #expect(run.progress(at: 0).fraction == 0)
        // The frame that made the change took half a second.
        let late = run.progress(at: 0.5).fraction
        #expect(close(late, AnimationRun.longestFirstStep, 1e-9))
        #expect(close(run.progress(at: 0.6).fraction, 0.1 + AnimationRun.longestFirstStep, 1e-9))
        #expect(!run.isDone(at: 1.4))
        #expect(run.isDone(at: 0.5 - AnimationRun.longestFirstStep + 1.001))
    }

    @Test func aFrameOnTimeLeavesTheStartAlone() {
        let run = AnimationRun(.linear(duration: 1), start: 0)
        #expect(run.progress(at: 0).fraction == 0)
        // Linear is a Bézier, solved to within 1e-7.
        #expect(close(run.progress(at: frame).fraction, frame, 1e-6))
        #expect(close(run.progress(at: 0.5).fraction, 0.5, 1e-6))
    }
}

// MARK: - Velocity tracking

@MainActor
@Suite
struct VelocityTrackingTests {

    private func close(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func twoChangesGiveTheirSpeed() {
        var sampler = VelocitySampler<Double>()
        #expect(sampler.velocity(at: 0) == nil)
        sampler.add(0, at: 0)
        #expect(sampler.velocity(at: 0) == nil)
        sampler.add(10, at: 0.01)
        #expect(close(sampler.velocity(at: 0.01) ?? 0, 1000, 1e-9))
    }

    @Test func theOlderPairCountsForThreeQuarters() {
        var sampler = VelocitySampler<Double>()
        sampler.add(0, at: 0)
        sampler.add(10, at: 0.01)   // 1000 per second
        sampler.add(30, at: 0.02)   // 2000 per second
        #expect(close(sampler.velocity(at: 0.02) ?? 0, 0.25 * 2000 + 0.75 * 1000, 1e-9))
        // A fourth drops the first.
        sampler.add(60, at: 0.03)   // 3000 per second
        #expect(close(sampler.velocity(at: 0.03) ?? 0, 0.25 * 3000 + 0.75 * 2000, 1e-9))
    }

    @Test func aChangeInTheSameFrameReplacesTheLast() {
        var sampler = VelocitySampler<Double>()
        sampler.add(0, at: 0)
        sampler.add(10, at: 0.01)
        sampler.add(20, at: 0.01)
        #expect(close(sampler.velocity(at: 0.01) ?? 0, 2000, 1e-9))
    }

    @Test func theSpeedFadesAndIsForgotten() {
        var sampler = VelocitySampler<Double>()
        sampler.add(0, at: 0)
        sampler.add(10, at: 0.01)
        // 0.2% a millisecond.
        #expect(close(sampler.velocity(at: 0.11) ?? 0, 1000 * pow(0.998, 100), 1e-6))
        #expect(sampler.velocity(at: 2.02) == nil)
    }

    @Test func aSpringSetsOffAtTheTrackedSpeed() throws {
        let motion = try #require(Motion<Double>.begin(
            offset: 100, previous: nil, tracked: 800, animation: .spring(duration: 0.5), at: 0
        ))
        #expect(close(motion.velocity(at: 0), 800, 1e-6))
        // Flung on past where it was let go before turning back.
        #expect(motion.displacement(at: 0.05).value > 100)
    }

    @Test func anEaseIgnoresTheTrackedSpeed() throws {
        let motion = try #require(Motion<Double>.begin(
            offset: 100, previous: nil, tracked: 800, animation: .easeInOut(duration: 0.5), at: 0
        ))
        // An ease starts flat: its own speed, nowhere near the 800 tracked.
        #expect(abs(motion.velocity(at: 0)) < 5)
    }
}

/// A drag that logs whether each of its callbacks ran with velocity
/// tracked.
@View
struct TrackedDrag {
    let log: Log
    let simultaneous: Bool

    var body: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { _ in log("changed \(TransactionScope.current?.tracksVelocity == true)") }
            .onEnded { _ in log("ended \(TransactionScope.current?.tracksVelocity == true)") }
        let content = Color.red.frame(width: 200, height: 200)
        if simultaneous {
            content.simultaneousGesture(drag)
        } else {
            content.gesture(drag)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct GestureVelocityTrackingTests {

        @Test(arguments: [false, true])
        func aDragsChangesTrackVelocityAndItsEndDoesNot(simultaneous: Bool) async {
            let log = Log()
            let harness = Harness(TrackedDrag(log: log, simultaneous: simultaneous))
            await harness.drag(from: Point(x: 100, y: 100), through: [Point(x: 120, y: 100), Point(x: 140, y: 100)])
            let entries = log.take()
            #expect(entries.contains("changed true"))
            #expect(!entries.contains("changed false"))
            #expect(entries.last == "ended false")
        }
    }
}
