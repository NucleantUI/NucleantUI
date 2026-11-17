//
//  ScrollObserversTests.swift
//  NucleantUITests
//
//  Watching a scroll view: how much of a rect is in view, then hosted scroll
//  views under `.onScrollGeometryChange`, `.onScrollPhaseChange` (both) and
//  `.onScrollTargetVisibilityChange`.
//

import Foundation
import Testing
@testable import NucleantUI

struct VisibleFractionTests {

    private let viewport = Rect(x: 0, y: 0, width: 200, height: 200)

    @Test(arguments: [
        (Rect(x: 10, y: 10, width: 50, height: 50), 1.0),
        (Rect(x: 0, y: 175, width: 200, height: 50), 0.5),
        (Rect(x: -25, y: 0, width: 50, height: 200), 0.5),
        (Rect(x: 150, y: 150, width: 100, height: 100), 0.25),
        (Rect(x: 0, y: 250, width: 200, height: 50), 0),
        // Touching the edge from outside is not in view.
        (Rect(x: 0, y: 200, width: 200, height: 50), 0),
    ] as [(Rect, Double)])
    func theShareOfARectsAreaInView(frame: Rect, fraction: Double) {
        #expect(frame.visibleFraction(in: viewport) == fraction)
    }

    @Test(arguments: [
        (Rect(x: 50, y: 50, width: 0, height: 0), 1.0),
        (Rect(x: 300, y: 50, width: 0, height: 10), 0),
    ] as [(Rect, Double)])
    func aRectWithNoAreaIsInViewWhenItLiesInside(frame: Rect, fraction: Double) {
        #expect(frame.visibleFraction(in: viewport) == fraction)
    }
}

// MARK: - Hosted

/// What the phase observers were told, with the context.
@MainActor
final class PhaseProbe {
    var changes: [(old: ScrollPhase, new: ScrollPhase, context: ScrollPhaseChangeContext?)] = []
    var targetIDs: [[Int]] = []

    /// The changes as "old→new", emptied.
    func take() -> [String] {
        defer { changes.removeAll() }
        return changes.map { "\($0.old)→\($0.new)" }
    }
}

/// 1000 tall in 200, 10 down from the top margin, reporting its offset.
@View
struct GeometryObserved {
    let log: Log

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 1000)
        }
        .contentMargins(.top, 10)
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y } action: { old, new in
            log("\(Int(old))→\(Int(new))")
        }
    }
}

@View
struct PastFiftyObserved {
    let log: Log

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 1000)
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 50 } action: { old, new in
            log("\(old)→\(new)")
        }
    }
}

/// Two scroll views one over the other, watched together.
@View
struct TwoScrollsObserved {
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { Color.blue.frame(height: 1000) }.frame(height: 100)
            ScrollView { Color.green.frame(height: 1000) }.frame(height: 100)
        }
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y } action: { _, new in
            log("\(Int(new))")
        }
    }
}

/// A sideways strip inside a watched scroll view.
@View
struct NestedObserved {
    let log: Log

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal) { Color.green.frame(width: 1000, height: 100) }
                Color.blue.frame(height: 1000)
            }
        }
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.x } action: { _, new in
            log("\(Int(new))")
        }
    }
}

@View
struct PhaseObserved {
    let probe: PhaseProbe

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 10_000)
        }
        .onScrollPhaseChange { old, new in
            probe.changes.append((old, new, nil))
        }
    }
}

@View
struct PhaseWithContextObserved {
    let probe: PhaseProbe

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 10_000)
        }
        .onScrollPhaseChange { old, new, context in
            probe.changes.append((old, new, context))
        }
    }
}

@View
struct TargetVisibilityObserved {
    let probe: PhaseProbe
    let threshold: Double

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { _ in
                    Color.blue.frame(height: 50)
                }
            }
            .scrollTargetLayout()
        }
        .onScrollTargetVisibilityChange(idType: Int.self, threshold: threshold) { ids in
            probe.targetIDs.append(ids)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollObservers {

        // MARK: Geometry

        @Test func geometryIsHandedOnFirstAsItIsThenAsItChanges() async {
            let log = Log()
            let harness = Harness(GeometryObserved(log: log))
            #expect(log.take() == ["-10→-10"], "it starts the top margin before zero")

            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -100)
            await harness.frames(2)
            #expect(log.take() == ["-10→90"])
        }

        @Test func onlyAChangeInTheValueWorkedOutCallsTheAction() async {
            let log = Log()
            let harness = Harness(PastFiftyObserved(log: log))
            #expect(log.take() == ["false→false"])
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -30)
            await harness.frames(2)
            #expect(log.take().isEmpty, "30 is not past 50")

            harness.host.scroll(dx: 0, dy: -40)
            await harness.frames(2)
            #expect(log.take() == ["false→true"])
        }

        @Test func onlyTheFirstScrollViewIsWatched() async {
            let log = Log()
            let harness = Harness(TwoScrollsObserved(log: log))
            _ = log.take()

            harness.host.pointerMoved(to: Point(x: 100, y: 150))
            harness.host.scroll(dx: 0, dy: -100)
            await harness.frames(2)
            #expect(log.take().isEmpty, "the second scroll view is not watched")

            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            harness.host.scroll(dx: 0, dy: -100)
            await harness.frames(2)
            #expect(log.take() == ["100"])
        }

        @Test func aScrollViewInsideTheWatchedOneIsNotWatched() async {
            let log = Log()
            let harness = Harness(NestedObserved(log: log))
            _ = log.take()
            harness.host.scrollsOnDrag = true

            await harness.drag(from: Point(x: 150, y: 50), through: [Point(x: 120, y: 50), Point(x: 50, y: 50)])
            await harness.frames(2)
            #expect(log.take().isEmpty)
        }

        // MARK: Phase

        @Test func aFingerIsTrackedThenInteractsThenLetsGo() async {
            let probe = PhaseProbe()
            let harness = Harness(PhaseObserved(probe: probe))
            harness.host.scrollsOnDrag = true

            harness.drag(from: Point(x: 100, y: 150), by: Point(x: 0, y: -60))
            await harness.frames(2)
            #expect(probe.take() == ["idle→tracking", "tracking→interacting", "interacting→idle"])
        }

        @Test func aFingerThatOnlyTouchesIsTrackedAndLetGo() async {
            let probe = PhaseProbe()
            let harness = Harness(PhaseObserved(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.tap(center)
            await harness.frames(1)
            #expect(probe.take() == ["idle→tracking", "tracking→idle"])
        }

        @Test func aWheelInteractsUntilItHasBeenStillAMoment() async {
            let probe = PhaseProbe()
            let harness = Harness(PhaseObserved(probe: probe))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -40)
            await harness.frames(2)
            #expect(probe.take() == ["idle→interacting"])

            await harness.settle(Scroller.wheelIdleDelay + 0.05)
            await harness.frames(1)
            #expect(probe.take() == ["interacting→idle"])
        }

        @Test func flungItDeceleratesAndTheContextHasTheSpeedItWasLetGoAt() async throws {
            let probe = PhaseProbe()
            let harness = Harness(PhaseWithContextObserved(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.flick(from: Point(x: 100, y: 180), step: Point(x: 0, y: -15), count: 6)
            await harness.frames(2)
            let release = try #require(probe.changes.first { $0.new == .decelerating })
            #expect(release.old == .interacting)
            let velocity = try #require(release.context?.velocity, "into decelerating, the speed it was let go at")
            #expect(velocity.y > 500)
            #expect(release.context?.geometry.contentOffset.y ?? 0 > 0)
            #expect(probe.changes.filter { $0.new != .decelerating }.allSatisfy { $0.context?.velocity == nil })
        }

        // MARK: Target visibility

        @Test func theViewsInViewAreHandedOnFirstThenAsTheyChange() async {
            let probe = PhaseProbe()
            let harness = Harness(TargetVisibilityObserved(probe: probe, threshold: 0.5))
            #expect(probe.targetIDs == [[0, 1, 2, 3]])
            harness.host.pointerMoved(to: center)

            // 125 down: row 2 has half of itself in view, row 6 half.
            harness.host.scroll(dx: 0, dy: -125)
            await harness.frames(2)
            #expect(probe.targetIDs.last == [2, 3, 4, 5, 6])
        }

        @Test func aHigherThresholdCountsOnlyViewsMoreInView() async {
            let probe = PhaseProbe()
            let harness = Harness(TargetVisibilityObserved(probe: probe, threshold: 0.9))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -125)
            await harness.frames(2)
            #expect(probe.targetIDs.last == [3, 4, 5])
        }

        @Test func aScrollThatChangesNoneOfThemHandsNothingOn() async {
            let probe = PhaseProbe()
            let harness = Harness(TargetVisibilityObserved(probe: probe, threshold: 0.5))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -10)
            await harness.frames(2)
            #expect(probe.targetIDs == [[0, 1, 2, 3]])
        }
    }
}
