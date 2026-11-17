//
//  VisualEffectTests.swift
//  NucleantUITests
//
//  Visual effects put on a draw context, their animatable data, and a
//  hosted `.visualEffect` worked out from where its view was placed.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct VisualEffectApplyTests {

    private let rect = Rect(x: 100, y: 100, width: 50, height: 20)

    /// The context `effect` leaves for a view at `rect`.
    private func applied(_ effect: some VisualEffect) -> DrawContext {
        var context = DrawContext()
        effect._apply(to: &context, in: rect)
        return context
    }

    @Test func theEmptyEffectChangesNothing() {
        let context = applied(EmptyVisualEffect())
        #expect(context.transform == .identity)
        #expect(context.opacity == 1)
    }

    @Test func anOffsetMovesTheDrawing() {
        let context = applied(EmptyVisualEffect().offset(x: 10, y: -5))
        #expect(context.transform.apply(to: Point(x: 100, y: 100)) == Point(x: 110, y: 95))
    }

    @Test(arguments: [
        (UnitPoint.center, Point(x: 100, y: 100), Point(x: 75, y: 90)),
        (.topLeading, Point(x: 100, y: 100), Point(x: 100, y: 100)),
        (.topLeading, Point(x: 150, y: 120), Point(x: 200, y: 140)),
    ])
    func aScaleGrowsAboutItsAnchor(anchor: UnitPoint, point: Point, expected: Point) {
        let context = applied(EmptyVisualEffect().scaleEffect(2, anchor: anchor))
        #expect(context.transform.apply(to: point) == expected)
    }

    @Test func aRotationTurnsAboutItsAnchor() {
        let context = applied(EmptyVisualEffect().rotationEffect(.degrees(90), anchor: .topLeading))
        let turned = context.transform.apply(to: Point(x: 110, y: 100))
        #expect(abs(turned.x - 100) < 1e-9)
        #expect(abs(turned.y - 110) < 1e-9)
    }

    @Test func aTransformIsAboutTheViewsTopLeadingCorner() {
        let context = applied(EmptyVisualEffect().transformEffect(.scale(x: 3, y: 3)))
        #expect(context.transform.apply(to: Point(x: 110, y: 100)) == Point(x: 130, y: 100))
    }

    @Test(arguments: [(0.5, 0.5), (2.0, 1.0), (-1.0, 0.0)])
    func opacityFadesTheContextClampedToZeroToOne(opacity: Double, expected: Double) {
        #expect(applied(EmptyVisualEffect().opacity(opacity)).opacity == expected)
    }

    @Test func anEffectWrittenLaterIsTheOuterOne() {
        // Moved 10, then the whole doubled about the top leading corner:
        // the move is doubled too.
        let context = applied(EmptyVisualEffect().offset(x: 10).scaleEffect(2, anchor: .topLeading))
        #expect(context.transform.apply(to: Point(x: 100, y: 100)) == Point(x: 120, y: 100))
    }

    @Test func aChainInterpolatesEveryEffectsNumbersTogether() {
        let from = EmptyVisualEffect().offset(x: 0, y: 20).opacity(1)
        let to = EmptyVisualEffect().offset(x: 100, y: 60).opacity(0)
        var halfway = from
        halfway.animatableData = from.animatableData + (to.animatableData - from.animatableData).scaled(by: 0.5)

        let context = applied(halfway)
        #expect(context.opacity == 0.5)
        #expect(context.transform.apply(to: .zero) == Point(x: 50, y: 40))
    }
}

// MARK: - Hosted

@MainActor
final class EffectProbe {
    var frame: Rect = .zero
    var taps = 0
}

/// A 50×50 square moved right by its own width, reporting where it is
/// drawn.
@View
struct SelfOffsetSquare {
    let probe: EffectProbe

    var body: some View {
        VStack(spacing: 0) {
            Button { probe.taps += 1 } label: {
                Color.red.frame(width: 50, height: 50)
            }
            .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { probe.frame = $0 }
            .visualEffect { content, proxy in
                content.offset(x: proxy.size.width)
            }
            Spacer()
        }
        .frame(width: 200, height: 200, alignment: .topLeading)
    }
}

/// A square moved by how far down the scroll view it is.
@View
struct ScrolledEffectSquare {
    let probe: EffectProbe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 100)
                Color.red.frame(width: 50, height: 50)
                    .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { probe.frame = $0 }
                    .visualEffect { content, proxy in
                        content.offset(x: proxy.frame(in: .scrollView).minY)
                    }
                Color.clear.frame(height: 1000)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct VisualEffects {

        @Test func theEffectIsWorkedOutFromTheViewsOwnGeometry() {
            let probe = EffectProbe()
            _ = Harness(SelfOffsetSquare(probe: probe))
            #expect(probe.frame == Rect(x: 50, y: 0, width: 50, height: 50))
        }

        @Test func theViewIsHitWhereTheEffectDrawsIt() async {
            let probe = EffectProbe()
            let harness = Harness(SelfOffsetSquare(probe: probe))
            await harness.tap(Point(x: 25, y: 25))
            #expect(probe.taps == 0, "where layout put it, nothing is drawn")
            await harness.tap(Point(x: 75, y: 25))
            #expect(probe.taps == 1)
        }

        @Test func aScrollThatMovesTheViewWorksTheEffectOutAgain() async {
            let probe = EffectProbe()
            let harness = Harness(ScrolledEffectSquare(probe: probe))
            #expect(probe.frame.minX == 100)

            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -60)
            await harness.frames(2)
            #expect(probe.frame.minX == 40)
            #expect(probe.frame.minY == 40)
        }
    }
}
