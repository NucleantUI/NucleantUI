//
//  ScrollerTests.swift
//  NucleantUITests
//
//  A scroll view's own engine, driven directly at chosen times — no host,
//  no clock: a finger dragging and letting go, a wheel, scrolls the app
//  asks for, requests worked out as the content is placed, an edge kept
//  to, and which view of a target layout is in front.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct ScrollerTests {

    private static let viewport = Size(width: 200, height: 200)

    /// A scroller placed at time 0 in a 200×200 viewport over `content`.
    private func makeScroller(
        content: Size = Size(width: 200, height: 1000),
        axes: Axis.Set = .vertical
    ) -> Scroller {
        let scroller = Scroller()
        scroller.axes = axes
        _ = scroller.place(viewport: Self.viewport, contentSize: content, at: 0)
        return scroller
    }

    /// A finger moving the content up by `step` every 10 ms, `count` times
    /// from time 0, and lifted at the last move: let go at `step` per 10 ms.
    private func flick(_ scroller: Scroller, step: Double, count: Int) {
        scroller.beginDrag(at: 0)
        for index in 1...count {
            scroller.drag(by: Point(x: 0, y: -step), at: Double(index) * 0.01)
        }
        scroller.endDrag(at: Double(count) * 0.01)
    }

    /// Placed every sixtieth of a second from `start` until it stops moving
    /// (or ten seconds pass); the time it stopped.
    @discardableResult
    private func settle(_ scroller: Scroller, from start: Double, content: Size = Size(width: 200, height: 1000)) -> Double {
        var time = start
        while scroller.isMoving, time < start + 10 {
            time += 1.0 / 60
            _ = scroller.place(viewport: Self.viewport, contentSize: content, at: time)
        }
        return time
    }

    /// A node to stand for the scroll view, or a view placed at `frame`.
    private func node(_ frame: Rect = .zero) -> ViewNode {
        let node = ContentNode(content: GroupContent())
        node.frame = frame
        return node
    }

    // MARK: - A finger

    @Test func aFingerMovesTheContentWithItAlongItsAxisOnly() {
        let scroller = makeScroller()
        scroller.beginDrag(at: 0)
        scroller.drag(by: Point(x: -30, y: -50), at: 0.01)
        #expect(scroller.offset == Point(x: 0, y: 50))
        #expect(scroller.phase == .interacting)
        #expect(scroller.isDragging)
    }

    @Test(arguments: [true, false])
    func pastTheTopTheFingerPullsByTheRubberBandOnlyWhenItBounces(bounces: Bool) {
        let scroller = makeScroller()
        scroller.bouncesVertically = bounces
        scroller.beginDrag(at: 0)
        scroller.drag(by: Point(x: 0, y: 100), at: 0.01)
        let expected = bounces ? -ScrollPhysics.rubberBand(100, dimension: 200) : 0
        #expect(abs(scroller.offset.y - expected) < 1e-9)
    }

    @Test func flungItCarriesOnAndComesToRestWhereItsSpeedTakesIt() {
        let scroller = makeScroller(content: Size(width: 200, height: 10_000))
        flick(scroller, step: 10, count: 5)
        #expect(scroller.offset.y == 50)
        #expect(scroller.isMoving)
        #expect(scroller.phase == .decelerating)

        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 10_000), at: 0.3)
        #expect(scroller.offset.y > 150, "1000 pt/s on, after a quarter of a second")

        settle(scroller, from: 0.3, content: Size(width: 200, height: 10_000))
        #expect(scroller.phase == .idle)
        #expect(abs(scroller.offset.y - ScrollPhysics.projectedEnd(from: 50, velocity: 1000)) < 1)
    }

    @Test func heldStillBeforeLiftingItStaysWhereItIs() {
        let scroller = makeScroller()
        scroller.beginDrag(at: 0)
        scroller.drag(by: Point(x: 0, y: -40), at: 0.02)
        scroller.endDrag(at: 0.2)
        #expect(scroller.isMoving == false)
        #expect(scroller.phase == .idle)
        #expect(scroller.offset.y == 40)
    }

    @Test func caughtWhileMovingItStopsWhereItIs() {
        let scroller = makeScroller(content: Size(width: 200, height: 10_000))
        #expect(scroller.catchMotion(at: 0) == false, "nothing to catch at rest")

        flick(scroller, step: 10, count: 5)
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 10_000), at: 0.2)
        #expect(scroller.catchMotion(at: 0.2))
        let caught = scroller.offset
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 10_000), at: 1)
        #expect(scroller.offset == caught)
        #expect(scroller.isMoving == false)
        #expect(scroller.isDragging)
    }

    @Test func caughtPastAnEdgeTheFingerTakesItFromWhereItShows() throws {
        let scroller = makeScroller()
        scroller.beginDrag(at: 0)
        scroller.drag(by: Point(x: 0, y: 100), at: 0.01)
        scroller.endDrag(at: 0.5)
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1000), at: 0.55)
        let showing = scroller.offset
        try #require(showing.y < 0, "still past the top while it springs back")

        #expect(scroller.catchMotion(at: 0.55))
        scroller.drag(by: .zero, at: 0.56)
        #expect(abs(scroller.offset.y - showing.y) < 1e-9, "no jump when caught")
    }

    // MARK: - A wheel

    @Test func aWheelMovesItInsideItsEdgesOnly() {
        let scroller = makeScroller()
        scroller.wheel(by: Point(x: 0, y: 50), at: 0)
        #expect(scroller.offset.y == 0)

        scroller.wheel(by: Point(x: 0, y: -300), at: 0.01)
        #expect(scroller.offset.y == 300)
        #expect(scroller.phase == .interacting)

        scroller.wheel(by: Point(x: 0, y: -5000), at: 0.02)
        #expect(scroller.offset.y == 800)
    }

    // MARK: - Where the app asks

    @Test func aScrollWithoutAnimationGoesAtOnce() {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: 400), animation: nil, at: 0)
        #expect(scroller.offset.y == 400)
        #expect(scroller.phase == .idle)
    }

    @Test func alongALinearAnimationItIsHalfwayAtHalfTimeAndAnimatingUntilThere() {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: 400), animation: .linear(duration: 1), at: 0)
        #expect(scroller.phase == .animating)

        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1000), at: 0.5)
        #expect(abs(scroller.offset.y - 200) < 1e-6)

        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1000), at: 1.1)
        #expect(scroller.offset.y == 400)
        #expect(scroller.phase == .idle)
    }

    @Test func anEndlessAnimationHasNoEndToGoAlongSoItGoesAtOnce() {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: 400), animation: .linear(duration: 1).repeatForever(), at: 0)
        #expect(scroller.offset.y == 400)
        #expect(scroller.phase == .idle)
    }

    @Test(arguments: [(-300.0, 0.0), (5000, 800)])
    func aScrollPastAnEdgeStopsAtTheEdge(asked: Double, reached: Double) {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: asked), animation: nil, at: 0)
        #expect(scroller.offset.y == reached)
    }

    @Test func aTargetBehaviorTakesAFlingToRestOnAPage() {
        let scroller = makeScroller(content: Size(width: 200, height: 2000))
        scroller.targetBehavior = ScrollTargetBehaviorEntry(.paging)
        flick(scroller, step: 10, count: 5)
        settle(scroller, from: 0.05, content: Size(width: 200, height: 2000))
        #expect(scroller.offset.y == 200, "one page on, however far the speed would have carried it")
        #expect(scroller.phase == .idle)
    }

    // MARK: - Requests

    @Test func aRequestIsGoneToOnceTheContentIsPlaced() {
        let scroller = makeScroller()
        scroller.request({ _, _ in (Point(x: 0, y: 300), true) }, animation: nil)
        #expect(scroller.offset.y == 0, "nothing moves before the content is placed")

        #expect(scroller.endPlacingContent(node: node(), at: 0))
        #expect(scroller.offset.y == 300)
    }

    @Test func aRequestIsWorkedOutAgainUntilItIsExactAndHoldsStill() {
        let scroller = makeScroller()
        var answers: [(Double, Bool)] = [(500, false), (520, true)]
        var asked = 0
        scroller.request({ _, _ in
            asked += 1
            let (y, exact) = answers.isEmpty ? (520, true) : answers.removeFirst()
            return (Point(x: 0, y: y), exact)
        }, animation: nil)

        for _ in 0..<20 { _ = scroller.endPlacingContent(node: node(), at: 0) }
        #expect(
            asked == 2 + Scroller.ScrollRequest.stablePasses,
            "asked until the exact answer has held for the stable passes, then no more"
        )
        #expect(scroller.offset.y == 520)
        #expect(scroller.hasPendingRequest == false)
    }

    @Test func aRequestThatNeverResolvesIsGivenUpOn() {
        let scroller = makeScroller()
        var asked = 0
        scroller.request({ _, _ in
            asked += 1
            return nil
        }, animation: nil)
        for _ in 0..<(Scroller.ScrollRequest.maximumPasses + 10) {
            _ = scroller.endPlacingContent(node: node(), at: 0)
        }
        #expect(asked == Scroller.ScrollRequest.maximumPasses)
        #expect(scroller.offset.y == 0)
    }

    @Test func pinnedToTheBottomItKeepsToItUntilTheUserMovesIt() {
        let scroller = makeScroller()
        scroller.pin(to: .bottom, animation: nil)
        while scroller.hasPendingRequest { _ = scroller.endPlacingContent(node: node(), at: 0) }
        #expect(scroller.offset.y == 800)

        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1200), at: 0.1)
        #expect(scroller.endPlacingContent(node: node(), at: 0.1))
        #expect(scroller.offset.y == 1000)

        scroller.beginDrag(at: 0.2)
        scroller.drag(by: Point(x: 0, y: 100), at: 0.21)
        scroller.endDrag(at: 0.5)
        settle(scroller, from: 0.5, content: Size(width: 200, height: 1200))
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1400), at: 20)
        #expect(scroller.endPlacingContent(node: node(), at: 20) == false)
        #expect(scroller.offset.y == 900, "where the finger left it, not the new bottom")
    }

    // MARK: - Geometry

    @Test(arguments: [
        (Edge.top, Point(x: 300, y: 0)),
        (.bottom, Point(x: 300, y: 800)),
        (.leading, Point(x: 0, y: 300)),
        (.trailing, Point(x: 800, y: 300)),
    ])
    func eachEdgeIsAnOffsetThatKeepsTheOtherAxis(edge: Edge, expected: Point) {
        let scroller = makeScroller(content: Size(width: 1000, height: 1000), axes: [.horizontal, .vertical])
        scroller.scroll(to: Point(x: 300, y: 300), animation: nil, at: 0)
        #expect(scroller.offset(at: edge) == expected)
    }

    @Test(arguments: [
        // Already in view: nothing moves.
        (Rect(x: 0, y: 450, width: 200, height: 50), UnitPoint?.none, 300.0),
        // Below: its bottom at the viewport's.
        (Rect(x: 0, y: 600, width: 200, height: 50), nil, 450),
        // Above: its top at the viewport's.
        (Rect(x: 0, y: 100, width: 200, height: 50), nil, 100),
        // Taller than the viewport: its top.
        (Rect(x: 0, y: 600, width: 200, height: 300), nil, 600),
        (Rect(x: 0, y: 600, width: 200, height: 50), .top, 600),
        (Rect(x: 0, y: 600, width: 200, height: 50), .center, 525),
        (Rect(x: 0, y: 600, width: 200, height: 50), .bottom, 450),
        // Near the end: no further than the end.
        (Rect(x: 0, y: 950, width: 200, height: 50), .top, 800),
    ])
    func showingARectTakesTheLeastMoveOrItsAnchor(rect: Rect, anchor: UnitPoint?, expected: Double) {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: 300), animation: nil, at: 0)
        #expect(scroller.offset(showing: rect, anchor: anchor).y == expected)
    }

    @Test(arguments: [(UnitPoint?.none, 5), (.center, 7), (.bottom, 9)])
    func theViewInFrontIsTheFirstInViewOrTheOneUnderTheAnchor(anchor: UnitPoint?, expected: Int) throws {
        let scroller = makeScroller()
        let rows = (0..<20).map { node(Rect(x: 0, y: Double($0) * 50, width: 200, height: 50)) }
        scroller.beginPlacingContent(at: .zero)
        scroller.addTargets(rows)
        _ = scroller.endPlacingContent(node: node(), at: 0)
        scroller.scroll(to: Point(x: 0, y: 260), animation: nil, at: 0)

        let front = try #require(scroller.positionedView(anchor: anchor))
        #expect(rows.firstIndex { $0 === front } == expected)
    }

    @Test func targetFramesAreInTheContentsOwnSpace() {
        let scroller = makeScroller()
        scroller.beginPlacingContent(at: Point(x: 10, y: -300))
        scroller.addTargets([node(Rect(x: 10, y: -100, width: 50, height: 50))])
        _ = scroller.endPlacingContent(node: node(), at: 0)
        #expect(scroller.targetFrames == [Rect(x: 0, y: 200, width: 50, height: 50)])
    }

    @Test func atRestItIsTakenBackInsideWhenTheContentShrinks() {
        let scroller = makeScroller()
        scroller.scroll(to: Point(x: 0, y: 800), animation: nil, at: 0)
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 500), at: 1)
        #expect(scroller.offset.y == 300)
    }
}
