//
//  TransformedClipTests.swift
//
//  A clip set under a `.scaleEffect` or `.rotationEffect` cuts the frame as
//  it is shown, not the frame layout gave it.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct TransformedClipTests {

    private let frame = Rect(x: 10, y: 10, width: 40, height: 20)

    @Test func clipWithoutTransformIsTheFrame() {
        let context = DrawContext().clipped(to: frame)
        #expect(context.clip == frame)
        #expect(context.transformedClips.isEmpty)
    }

    @Test func scaledClipIsTheScaledFrame() {
        var context = DrawContext()
        context.transform = .around(Point(x: 30, y: 20), .scale(x: 2, y: 2))
        let clipped = context.clipped(to: frame, cornerRadius: 4)
        #expect(clipped.clip == Rect(x: -10, y: 0, width: 80, height: 40))
        #expect(clipped.clipCornerRadius == 8)
        #expect(clipped.transformedClips.isEmpty)
    }

    @Test func rotatedClipTurnsWithTheFrame() {
        var context = DrawContext()
        let turn = Transform.around(Point(x: 30, y: 20), .rotation(.degrees(90)))
        context.transform = turn
        let clipped = context.clipped(to: frame)
        #expect(clipped.transformedClips == [TransformedClip(rect: frame, transform: turn)])
        // The box around it still bounds the clip: the frame on its side.
        let box = clipped.clip!
        #expect(abs(box.minX - 20) < 1e-9 && abs(box.minY - 0) < 1e-9)
        #expect(abs(box.width - 20) < 1e-9 && abs(box.height - 40) < 1e-9)
    }

    @Test func outerClipStaysUnderATurnedOne() {
        var context = DrawContext().clipped(to: Rect(x: 0, y: 0, width: 25, height: 100))
        context.transform = .around(Point(x: 30, y: 20), .rotation(.degrees(90)))
        let clipped = context.clipped(to: frame)
        #expect(clipped.transformedClips.count == 1)
        #expect(clipped.clip!.maxX <= 25)
    }
}
