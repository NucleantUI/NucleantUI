//
//  ScrollBounceBehaviorTests.swift
//  NucleantUITests
//
//  `.scrollBounceBehavior`: when a scroll view bounces, which axes the
//  modifier sets, and a hosted scroll view that does not bounce handing a
//  finger or a wheel it cannot take to the scroll view around it.
//

import Foundation
import Testing
@testable import NucleantUI

struct ScrollBounceBehaviorTests {

    @Test(arguments: [
        (ScrollBounceBehavior.automatic, false, true),
        (.automatic, true, true),
        (.always, false, true),
        (.always, true, true),
        (.basedOnSize, false, false),
        (.basedOnSize, true, true),
    ])
    func itBouncesAlwaysOrOnlyWithContentLongerThanTheScrollView(
        behavior: ScrollBounceBehavior,
        contentIsLonger: Bool,
        bounces: Bool
    ) {
        #expect(behavior.bounces(contentIsLonger: contentIsLonger) == bounces)
    }
}

@MainActor
struct ScrollerMovingAxesTests {

    /// A vertical scroller placed in 200×200 over content `height` tall.
    private func scroller(height: Double, bounce: ScrollBounceBehavior) -> Scroller {
        let scroller = Scroller()
        scroller.verticalBounce = bounce
        _ = scroller.place(viewport: Size(width: 200, height: 200), contentSize: Size(width: 200, height: height), at: 0)
        return scroller
    }

    @Test(arguments: [
        (100.0, ScrollBounceBehavior.basedOnSize, false),
        (100, .always, true),
        (1000, .basedOnSize, true),
    ])
    func itMovesAlongAnAxisWithSomethingToScrollOrBouncingThere(height: Double, bounce: ScrollBounceBehavior, moves: Bool) {
        #expect(scroller(height: height, bounce: bounce).moves(along: .vertical) == moves)
    }

    @Test func itNeverMovesAlongAnAxisItDoesNotScroll() {
        let scroller = scroller(height: 1000, bounce: .always)
        #expect(!scroller.moves(along: .horizontal))
    }
}

// MARK: - Hosted

/// The bounce behaviors a view is placed under.
@MainActor
final class BounceProbe {
    var vertical: ScrollBounceBehavior.Kind?
    var horizontal: ScrollBounceBehavior.Kind?
}

@View
struct BounceReader {
    let probe: BounceProbe
    @Environment(\.verticalScrollBounceBehavior) private var vertical
    @Environment(\.horizontalScrollBounceBehavior) private var horizontal

    var body: some View {
        let _ = probe.vertical = vertical.kind
        let _ = probe.horizontal = horizontal.kind
        Color.clear
    }
}

/// Rows `height` tall in a scroll view under `behavior` for `axes`.
@View
struct BouncingScroll {
    let probe: ScrollProbe
    let height: Double
    let behavior: ScrollBounceBehavior

    var body: some View {
        ScrollView {
            ProbedRows(probe: probe, height: height)
        }
        .scrollBounceBehavior(behavior)
    }
}

/// A short scroll view under `inner` at the top of a long one: the long
/// one's content reported.
@View
struct ShortInsideLong {
    let probe: ScrollProbe
    let inner: ScrollBounceBehavior

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ScrollView {
                    Color.green.frame(height: 50)
                }
                .frame(height: 100)
                .scrollBounceBehavior(inner)
                Color.blue.frame(height: 2000)
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
    }
}

/// A sideways strip whose content fits, `.basedOnSize` for `axes`.
@View
struct ShortShelf {
    let probe: ScrollProbe
    let axes: Axis.Set

    var body: some View {
        ScrollView(.horizontal) {
            Color.green.frame(width: 100, height: 100)
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minX } action: { probe.leading = $0 }
        }
        .scrollBounceBehavior(.basedOnSize, axes: axes)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollBounceBehaviors {

        @Test func theModifierSetsTheVerticalAxisUnlessToldOtherwise() {
            let probe = BounceProbe()
            _ = Harness(BounceReader(probe: probe).scrollBounceBehavior(.basedOnSize))
            #expect(probe.vertical == .basedOnSize)
            #expect(probe.horizontal == .automatic)
        }

        @Test func theModifierSetsTheAxesItIsGiven() {
            let probe = BounceProbe()
            _ = Harness(BounceReader(probe: probe).scrollBounceBehavior(.always, axes: [.horizontal, .vertical]))
            #expect(probe.vertical == .always)
            #expect(probe.horizontal == .always)
        }

        @Test(arguments: [(ScrollBounceBehavior.automatic, true), (.basedOnSize, false)])
        func aScrollViewWhoseContentFitsMovesUnderAFingerOnlyWhenItBounces(behavior: ScrollBounceBehavior, moves: Bool) {
            let probe = ScrollProbe()
            let harness = Harness(BouncingScroll(probe: probe, height: 100, behavior: behavior))
            harness.host.scrollsOnDrag = true

            harness.host.pointerDown(at: Point(x: 100, y: 50))
            harness.host.pointerMoved(to: Point(x: 100, y: 100))
            harness.host.pointerMoved(to: Point(x: 100, y: 150))
            harness.host.update()
            #expect((probe.top > 0) == moves)
            harness.host.pointerUp(at: Point(x: 100, y: 150))
        }

        @Test(arguments: [(ScrollBounceBehavior.always, 0.0), (.basedOnSize, -60)])
        func aFingerAShortScrollViewCannotTakeGoesToTheOneAroundIt(inner: ScrollBounceBehavior, outerTop: Double) async {
            let probe = ScrollProbe()
            let harness = Harness(ShortInsideLong(probe: probe, inner: inner))
            harness.host.scrollsOnDrag = true

            await harness.drag(from: Point(x: 100, y: 80), through: [Point(x: 100, y: 50), Point(x: 100, y: 20)])
            #expect(abs(probe.top - outerTop) < 0.001)
        }

        @Test(arguments: [(ScrollBounceBehavior.always, 0.0), (.basedOnSize, -30)])
        func soDoesAWheel(inner: ScrollBounceBehavior, outerTop: Double) {
            let probe = ScrollProbe()
            let harness = Harness(ShortInsideLong(probe: probe, inner: inner))

            harness.host.pointerMoved(to: Point(x: 100, y: 50))
            harness.host.scroll(dx: 0, dy: -30)
            harness.host.update()
            #expect(abs(probe.top - outerTop) < 0.001)
        }

        @Test(arguments: [(Axis.Set.vertical, true), (.horizontal, false)])
        func aBehaviorForOneAxisLeavesTheOtherBouncing(axes: Axis.Set, moves: Bool) {
            let probe = ScrollProbe()
            let harness = Harness(ShortShelf(probe: probe, axes: axes))
            harness.host.scrollsOnDrag = true

            harness.host.pointerDown(at: Point(x: 50, y: 50))
            harness.host.pointerMoved(to: Point(x: 100, y: 51))
            harness.host.pointerMoved(to: Point(x: 150, y: 52))
            harness.host.update()
            #expect((probe.leading > 0) == moves)
            harness.host.pointerUp(at: Point(x: 150, y: 52))
        }
    }
}
