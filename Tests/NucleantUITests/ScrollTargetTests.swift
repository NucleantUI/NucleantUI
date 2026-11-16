//
//  ScrollTargetTests.swift
//  NucleantUITests
//
//  Where a scroll comes to rest under `.scrollTargetBehavior`: pages,
//  views of a `.scrollTargetLayout()`, a behavior of the app's own.
//

import Foundation
import Testing
@testable import NucleantUI

@View
struct PagedScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<5) { _ in
                    Color.blue.frame(height: 200)
                }
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollTargetBehavior(.paging)
    }
}

@View
struct ErasedPagedScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<5) { _ in
                    Color.blue.frame(height: 200)
                }
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollTargetBehavior(AnyScrollTargetBehavior(.paging))
    }
}

@View
struct CardStrip {
    let probe: ScrollProbe
    let limit: ViewAlignedScrollTargetBehavior.LimitBehavior

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(0..<8) { _ in
                    Color.orange.frame(width: 150, height: 100)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minX } action: { probe.leading = $0 }
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: limit))
    }
}

/// Rests on multiples of a fifth of the container, and notes what it was
/// told.
struct FifthsBehavior: ScrollTargetBehavior {
    let seen: SeenContext

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let step = context.containerSize.height / 5
        target.rect.origin.y = (target.rect.origin.y / step).rounded() * step
        let container = context.containerSize
        let content = context.contentSize
        let axes = context.axes
        let scheme = context.colorScheme
        MainActor.assumeIsolated {
            seen.container = container
            seen.content = content
            seen.axes = axes
            seen.scheme = scheme
        }
    }
}

@MainActor
final class SeenContext {
    var container: Size = .zero
    var content: Size = .zero
    var axes: Axis.Set = []
    var scheme: ColorScheme?
}

@View
struct FifthsScroll {
    let probe: ScrollProbe
    let seen: SeenContext

    var body: some View {
        ScrollView {
            Color.green.frame(height: 1000)
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollTargetBehavior(FifthsBehavior(seen: seen))
        .colorScheme(.dark)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollTargets {

        private func frames(_ count: Int, _ harness: Harness) async {
            for _ in 0..<count { await harness.settle(1.0 / 60) }
        }

        /// A finger moved by `distance` at once — no speed when it lifts.
        private func drag(_ harness: Harness, from: Point, by distance: Point) async {
            harness.host.pointerDown(at: from)
            harness.host.pointerMoved(to: from + distance / 2)
            harness.host.pointerMoved(to: from + distance)
            harness.host.pointerUp(at: from + distance)
            await frames(50, harness)
        }

        private func flick(_ harness: Harness, from: Point, step: Point, count: Int) async {
            harness.host.pointerDown(at: from)
            var point = from
            for _ in 0..<count {
                try? await Task.sleep(for: .milliseconds(10))
                point += step
                harness.host.pointerMoved(to: point)
            }
            harness.host.pointerUp(at: point)
            await frames(60, harness)
        }

        @Test func pagingTurnsThePageWhenLetGoPastHalfOfIt() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            await drag(harness, from: Point(x: 100, y: 180), by: Point(x: 0, y: -120))
            #expect(probe.top == -200)

            await drag(harness, from: Point(x: 100, y: 180), by: Point(x: 0, y: -60))
            #expect(probe.top == -200)

            await drag(harness, from: Point(x: 100, y: 20), by: Point(x: 0, y: 130))
            #expect(probe.top == 0)
        }

        @Test func aFlingTurnsOnePageHoweverHard() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            await flick(harness, from: Point(x: 100, y: 190), step: Point(x: 0, y: -25), count: 6)
            #expect(probe.top == -200)

            // A short quick flick turns it too: its speed carries it past half.
            await flick(harness, from: Point(x: 100, y: 150), step: Point(x: 0, y: -12), count: 4)
            #expect(probe.top == -400)
        }

        @Test func aWheelGoneStillSettlesOnAPage() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -130)
            harness.host.update()
            #expect(probe.top == -130)
            await harness.settle(Scroller.wheelIdleDelay + 0.05)
            await frames(50, harness)
            #expect(probe.top == -200)
        }

        @Test func resizedAtRestItKeepsToThePageItWasOn() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.pointerMoved(to: center)
            for _ in 0..<2 {
                harness.host.scroll(dx: 0, dy: -200)
                await harness.settle(Scroller.wheelIdleDelay + 0.05)
                await frames(10, harness)
            }
            #expect(probe.top == -400)

            harness.host.setSize(Size(width: 200, height: 250))
            await frames(3, harness)
            #expect(probe.top == -500)
        }

        @Test func anErasedBehaviorDoesWhatItWraps() async {
            let probe = ScrollProbe()
            let harness = Harness(ErasedPagedScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            await drag(harness, from: Point(x: 100, y: 180), by: Point(x: 0, y: -120))
            #expect(probe.top == -200)
        }

        @Test func viewAlignedRestsOnTheNearestViewsLeadingEdge() async {
            let probe = ScrollProbe()
            let harness = Harness(CardStrip(probe: probe, limit: .never))
            harness.host.scrollsOnDrag = true

            // Cards every 160: 100 along is nearer 160 than 0.
            await drag(harness, from: Point(x: 180, y: 50), by: Point(x: -100, y: 0))
            #expect(probe.leading == -160)

            await drag(harness, from: Point(x: 180, y: 50), by: Point(x: -50, y: 0))
            #expect(probe.leading == -160)

            await drag(harness, from: Point(x: 20, y: 50), by: Point(x: 110, y: 0))
            #expect(probe.leading == 0)
        }

        @Test func limitedToOneAFlingMovesByOneView() async {
            let probe = ScrollProbe()
            let unlimited = Harness(CardStrip(probe: probe, limit: .never))
            unlimited.host.scrollsOnDrag = true
            await flick(unlimited, from: Point(x: 190, y: 50), step: Point(x: -25, y: 0), count: 6)
            #expect(probe.leading < -320)

            let limitedProbe = ScrollProbe()
            let limited = Harness(CardStrip(probe: limitedProbe, limit: .alwaysByOne))
            limited.host.scrollsOnDrag = true
            await flick(limited, from: Point(x: 190, y: 50), step: Point(x: -25, y: 0), count: 6)
            #expect(limitedProbe.leading == -160)
        }

        @Test func anAppsBehaviorIsToldTheScrollViewsGeometryAndEnvironment() async {
            let probe = ScrollProbe()
            let seen = SeenContext()
            let harness = Harness(FifthsScroll(probe: probe, seen: seen))
            harness.host.scrollsOnDrag = true

            await drag(harness, from: Point(x: 100, y: 180), by: Point(x: 0, y: -70))
            // Fifths of 200: 70 rests at 80.
            #expect(probe.top == -80)
            #expect(seen.container == Size(width: 200, height: 200))
            #expect(seen.content == Size(width: 200, height: 1000))
            #expect(seen.axes == .vertical)
            #expect(seen.scheme == .dark)
        }
    }
}
