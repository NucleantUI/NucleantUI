//
//  EffectGestureTests.swift
//  NucleantUITests
//
//  #31: a gesture attached after `.offset`, `.scaleEffect` or
//  `.rotationEffect` is hit where the view is drawn, as in SwiftUI — the
//  gesture is on the moved view — and not where layout placed it.
//

import Testing
@testable import NucleantUI

/// An 80×80 square in the middle of a 600×300 host — laid out at
/// 260…340 × 110…190 — moved by one effect, with a drag gesture attached
/// after it that logs where it started.
@View
struct EffectGestureSquare {
    let log: Log
    let effect: Effect

    enum Effect {
        case offset, grow, shrink, turn
    }

    var body: some View {
        ZStack(alignment: .center) {
            square
        }
    }

    @ViewBuilder
    private var square: some View {
        let base = Rectangle().fill(Color.blue).frame(width: 80, height: 80)
        let drag = DragGesture(minimumDistance: 0).onEnded { value in
            log("started at \(Int(value.startLocation.x)),\(Int(value.startLocation.y))")
        }
        switch effect {
        case .offset: base.offset(x: 180).gesture(drag)
        case .grow: base.scaleEffect(2).gesture(drag)
        case .shrink: base.scaleEffect(0.5).gesture(drag)
        case .turn: base.rotationEffect(.degrees(45)).gesture(drag)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct EffectGestureTests {

        private func press(_ effect: EffectGestureSquare.Effect, at point: Point) async -> [String] {
            let log = Log()
            let harness = Harness(EffectGestureSquare(log: log, effect: effect), size: Size(width: 600, height: 300))
            await harness.tap(point)
            return log.take()
        }

        @Test func aGestureAfterAnOffsetIsHitWhereTheViewIsDrawn() async {
            // Drawn at 440…520: its middle, in the square's own space.
            #expect(await press(.offset, at: Point(x: 480, y: 150)) == ["started at 40,40"])
            // Where it was laid out, there is nothing to press.
            #expect(await press(.offset, at: Point(x: 300, y: 150)) == [])
        }

        @Test func aGestureAfterAScaleIsHitWhereTheViewIsDrawn() async {
            // Twice the size, 220…380: past the laid-out edge, inside the
            // drawn one — 5 points in, in the square's own space.
            #expect(await press(.grow, at: Point(x: 230, y: 150)) == ["started at 5,40"])
            // Half the size, 280…320: inside the laid-out square, outside
            // the drawn one.
            #expect(await press(.shrink, at: Point(x: 265, y: 150)) == [])
            #expect(await press(.shrink, at: Point(x: 300, y: 150)) == ["started at 40,40"])
        }

        @Test func aGestureAfterARotationIsHitWhereTheViewIsDrawn() async {
            // Turned 45°, a diamond whose top corner reaches 56.6 points
            // above the middle: above the laid-out square, inside the drawn.
            #expect(await press(.turn, at: Point(x: 300, y: 100)).count == 1)
            // The laid-out corner is outside the diamond.
            #expect(await press(.turn, at: Point(x: 263, y: 113)) == [])
        }
    }
}
