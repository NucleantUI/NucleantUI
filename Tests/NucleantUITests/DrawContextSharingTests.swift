//
//  DrawContextSharingTests.swift
//  NucleantUITests
//
//  A draw context keeps what holds a reference — turned clips, a shader's
//  canvas input, the animation, the coordinate spaces — behind one object
//  that copies share, made again only when one of them changes.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct DrawContextSharingTests {

    private let space = CoordinateSpaceFrame(
        name: AnyHashable("list"),
        rect: Rect(x: 0, y: 0, width: 100, height: 100),
        transform: .identity
    )

    @Test func aCopyChangedInItsPlainPartSharesTheRest() {
        var outer = DrawContext()
        outer.coordinateSpaces.append(space)
        var inner = outer
        inner.opacity = 0.5
        inner.transform = .translation(x: 10, y: 0)
        inner.clip = Rect(x: 0, y: 0, width: 50, height: 50)
        #expect(inner.shared === outer.shared)
    }

    @Test func changingTheSharedPartLeavesTheCopyItCameFrom() {
        var outer = DrawContext()
        outer.animation = .easeInOut
        var inner = outer
        inner.coordinateSpaces.append(space)
        #expect(inner.shared !== outer.shared)
        #expect(outer.coordinateSpaces.isEmpty)
        #expect(inner.coordinateSpaces == [space])
        #expect(inner.animation == .easeInOut, "the other values come along")
    }

    @Test func settingTheValueItHoldsKeepsTheObject() {
        var context = DrawContext()
        context.animation = .linear
        let held = context.shared
        context.animation = .linear
        context.transformedClips = []
        context.shaderCanvasInput = nil
        #expect(context.shared === held)
        context.animation = nil
        #expect(context.shared !== held)
        #expect(context.animation == nil)
    }

    @Test func aRotatedClipRidesInTheSharedPart() {
        var context = DrawContext()
        context.transform = .around(Point(x: 50, y: 50), .rotation(.degrees(30)))
        let clipped = context.clipped(to: Rect(x: 0, y: 0, width: 100, height: 100))
        #expect(clipped.transformedClips.count == 1)
        #expect(context.transformedClips.isEmpty)
        #expect(clipped.drawState.transformedClips == clipped.transformedClips)
    }
}
