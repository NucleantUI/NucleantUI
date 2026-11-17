//
//  ScrollTargetBehaviorTests.swift
//  NucleantUITests
//
//  Where a scroll comes to rest: the built-in behaviors asked directly with
//  a context made here, then a hosted scroll view under `.scrollTarget-
//  Behavior` — a finger, a fling, a wheel, a resize, an app's own behavior.
//

import Foundation
import Testing
@testable import NucleantUI

/// What a behavior is asked with: a scroll that began at `start` along the
/// scrollable axis, in a 200-long container.
private func makeContext(
    start: Double = 0,
    axes: Axis.Set = .vertical,
    content: Size = Size(width: 200, height: 1000),
    frames: [Rect] = [],
    environment: EnvironmentValues = EnvironmentValues()
) -> ScrollTargetBehaviorContext {
    let origin = axes == .horizontal ? Point(x: start, y: 0) : Point(x: 0, y: start)
    return ScrollTargetBehaviorContext(
        originalTarget: ScrollTarget(rect: Rect(origin: origin, size: Size(width: 200, height: 200))),
        velocity: .zero,
        contentSize: content,
        containerSize: Size(width: 200, height: 200),
        axes: axes,
        environment: environment,
        targetFrames: frames
    )
}

/// Where `behavior` lets a scroll that would end at `proposed` rest.
private func landing(
    _ behavior: some ScrollTargetBehavior,
    proposing proposed: Double,
    _ context: ScrollTargetBehaviorContext
) -> Point {
    let origin = context.axes == .horizontal ? Point(x: proposed, y: 0) : Point(x: 0, y: proposed)
    var target = ScrollTarget(rect: Rect(origin: origin, size: context.containerSize))
    behavior.updateTarget(&target, context: context)
    return target.rect.origin
}

struct PagingScrollTargetBehaviorTests {

    @Test(arguments: [
        // Less than half a page: back.
        (0.0, 90.0, 0.0),
        // Past half: the next page.
        (0, 110, 200),
        // However far it would have gone: one page.
        (0, 900, 200),
        (400, 0, 200),
        (400, 450, 400),
        (400, 520, 600),
    ])
    func aScrollMovesAtMostOnePageFromWhereItBegan(start: Double, proposed: Double, expected: Double) {
        #expect(landing(.paging, proposing: proposed, makeContext(start: start)).y == expected)
    }

    @Test func theLastPageEndsWhereTheContentDoes() {
        // 1050 long: the last page starts at 850, not at 1000.
        let context = makeContext(start: 800, content: Size(width: 200, height: 1050))
        #expect(landing(.paging, proposing: 1000, context).y == 850)
    }

    @Test func contentShorterThanAPageRestsAtTheStart() {
        let context = makeContext(content: Size(width: 200, height: 120))
        #expect(landing(.paging, proposing: 80, context).y == 0)
    }

    @Test func theAxisItDoesNotScrollIsLeftAsItIs() {
        let context = makeContext(start: 0, axes: .horizontal, content: Size(width: 1000, height: 200))
        var target = ScrollTarget(rect: Rect(x: 130, y: 37, width: 200, height: 200))
        PagingScrollTargetBehavior().updateTarget(&target, context: context)
        #expect(target.rect.origin == Point(x: 200, y: 37))
    }

    @Test func anAnchorIsDropped() {
        var target = ScrollTarget(rect: Rect(x: 0, y: 130, width: 200, height: 200), anchor: .center)
        PagingScrollTargetBehavior().updateTarget(&target, context: makeContext())
        #expect(target.anchor == nil)
    }
}

struct ViewAlignedScrollTargetBehaviorTests {

    /// Eight cards 150 wide, 10 apart: leading edges every 160.
    private let cards = (0..<8).map { Rect(x: Double($0) * 160, y: 0, width: 150, height: 100) }

    private func strip(start: Double = 0) -> ScrollTargetBehaviorContext {
        makeContext(start: start, axes: .horizontal, content: Size(width: 1270, height: 100), frames: cards)
    }

    @Test(arguments: [
        (0.0, 0.0),
        (79, 0),
        (81, 160),
        (500, 480),
        // Past the last card that can get to the leading edge: the end.
        (1200, 1070),
    ])
    func aScrollRestsOnTheNearestViewsLeadingEdge(proposed: Double, expected: Double) {
        #expect(landing(ViewAlignedScrollTargetBehavior(limitBehavior: .never), proposing: proposed, strip()).x == expected)
    }

    @Test(arguments: [
        (ViewAlignedScrollTargetBehavior.LimitBehavior.always, 160.0),
        (.alwaysByOne, 160),
        // A 200-wide container shows one 150-wide card.
        (.alwaysByFew, 160),
        (.never, 960),
        (.automatic, 960),
    ])
    func aLimitHoldsAScrollToSoManyViews(limit: ViewAlignedScrollTargetBehavior.LimitBehavior, expected: Double) {
        #expect(landing(.viewAligned(limitBehavior: limit), proposing: 950, strip()).x == expected)
    }

    @Test func byAFewIsAsManyViewsAsTheContainerShows() {
        let context = makeContext(
            axes: .horizontal,
            content: Size(width: 2000, height: 100),
            frames: (0..<20).map { Rect(x: Double($0) * 100, y: 0, width: 100, height: 100) }
        )
        #expect(landing(.viewAligned(limitBehavior: .alwaysByFew), proposing: 1500, context).x == 200)
    }

    @Test func withNoScrollTargetLayoutTheTargetIsLeftAsItIs() {
        let context = makeContext(axes: .horizontal, content: Size(width: 1000, height: 200))
        #expect(landing(.viewAligned, proposing: 333, context).x == 333)
    }
}

struct AnyScrollTargetBehaviorTests {

    @Test(arguments: [90.0, 110, 900])
    func itDoesWhatTheBehaviorItWrapsDoes(proposed: Double) {
        let context = makeContext()
        #expect(landing(AnyScrollTargetBehavior(.paging), proposing: proposed, context)
            == landing(.paging, proposing: proposed, context))
    }

    @Test func itHasTheWrappedBehaviorsProperties() {
        let context = ScrollTargetBehaviorPropertiesContext(environment: EnvironmentValues(), axes: .vertical)
        #expect(AnyScrollTargetBehavior(.viewAligned).properties(context: context) == ScrollTargetBehaviorProperties())
    }
}

struct ScrollTargetBehaviorContextTests {

    @Test func itReadsTheScrollViewsEnvironmentByKeyPath() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        #expect(makeContext(environment: environment).colorScheme == .dark)
    }
}

// MARK: - Hosted

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

        @Test func aFingerLetGoPastHalfAPageTurnsIt() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            harness.drag(from: Point(x: 100, y: 180), by: Point(x: 0, y: -120))
            await harness.frames(50)
            #expect(probe.top == -200)

            harness.drag(from: Point(x: 100, y: 180), by: Point(x: 0, y: -60))
            await harness.frames(50)
            #expect(probe.top == -200, "less than half: back")

            harness.drag(from: Point(x: 100, y: 20), by: Point(x: 0, y: 130))
            await harness.frames(50)
            #expect(probe.top == 0)
        }

        @Test func aFlingTurnsOnePageHoweverHard() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.scrollsOnDrag = true

            await harness.flick(from: Point(x: 100, y: 190), step: Point(x: 0, y: -25), count: 6)
            await harness.frames(60)
            #expect(probe.top == -200)

            await harness.flick(from: Point(x: 100, y: 150), step: Point(x: 0, y: -12), count: 4)
            await harness.frames(60)
            #expect(probe.top == -400, "a short quick flick turns it too: its speed carries it past half")
        }

        @Test func aWheelGoneStillSettlesOnAPage() async {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -130)
            harness.host.update()
            #expect(probe.top == -130)
            await harness.settle(Scroller.wheelIdleDelay + 0.05)
            await harness.frames(50)
            #expect(probe.top == -200)
        }

        @Test func resizedAtRestItKeepsToThePageItWasOn() async throws {
            let probe = ScrollProbe()
            let harness = Harness(PagedScroll(probe: probe))
            harness.host.pointerMoved(to: center)
            for _ in 0..<2 {
                harness.host.scroll(dx: 0, dy: -200)
                await harness.settle(Scroller.wheelIdleDelay + 0.05)
                await harness.frames(10)
            }
            try #require(probe.top == -400, "on the third page before the resize")

            harness.host.setSize(Size(width: 200, height: 250))
            await harness.frames(3)
            #expect(probe.top == -500, "the third page of 250")
        }

        @Test func viewAlignedRestsOnTheNearestCard() async {
            let probe = ScrollProbe()
            let harness = Harness(CardStrip(probe: probe, limit: .never))
            harness.host.scrollsOnDrag = true

            harness.drag(from: Point(x: 180, y: 50), by: Point(x: -100, y: 0))
            await harness.frames(50)
            #expect(probe.leading == -160, "100 along is nearer 160 than 0")

            harness.drag(from: Point(x: 20, y: 50), by: Point(x: 110, y: 0))
            await harness.frames(50)
            #expect(probe.leading == 0)
        }

        @Test func limitedToOneAFlingMovesByOneCard() async {
            let probe = ScrollProbe()
            let harness = Harness(CardStrip(probe: probe, limit: .alwaysByOne))
            harness.host.scrollsOnDrag = true
            await harness.flick(from: Point(x: 190, y: 50), step: Point(x: -25, y: 0), count: 6)
            await harness.frames(60)
            #expect(probe.leading == -160)
        }

        @Test func anAppsBehaviorIsToldTheScrollViewsGeometryAndEnvironment() async {
            let probe = ScrollProbe()
            let seen = SeenContext()
            let harness = Harness(FifthsScroll(probe: probe, seen: seen))
            harness.host.scrollsOnDrag = true

            harness.drag(from: Point(x: 100, y: 180), by: Point(x: 0, y: -70))
            await harness.frames(50)
            #expect(probe.top == -80, "fifths of 200: 70 rests at 80")
            #expect(seen.container == Size(width: 200, height: 200))
            #expect(seen.content == Size(width: 200, height: 1000))
            #expect(seen.axes == .vertical)
            #expect(seen.scheme == .dark)
        }
    }
}
