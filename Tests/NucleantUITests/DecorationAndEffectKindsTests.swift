//
//  DecorationAndEffectKindsTests.swift
//  NucleantUITests
//
//  `.background` and `.overlay`, `.rotationEffect` and `.scaleEffect`: each
//  a node kind of its own, drawing as the one shared kind did.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct DecorationAndEffectKindsTests {

    private let size = Size(width: 100, height: 100)

    /// What `view` draws, centered at its own size: the root view itself is
    /// given the whole window.
    private func list<V: View>(_ view: V) -> DisplayList {
        OffscreenRender(environment: EnvironmentValues()).list(of: ZStack { view }, size: size)
    }

    /// The flat colors drawn, in paint order.
    private func colors(_ list: DisplayList) -> [Color] {
        list.commands.compactMap {
            if case .shape(let draw) = $0, case .color(let color)? = draw.fill?.kind { color } else { nil }
        }
    }

    @Test func aBackgroundIsPaintedBehindAndAnOverlayOver() {
        let red = Color(red: 1, green: 0, blue: 0), blue = Color(red: 0, green: 0, blue: 1)
        #expect(colors(list(blue.frame(width: 20, height: 20).background(red))) == [red, blue])
        #expect(colors(list(blue.frame(width: 20, height: 20).overlay(red))) == [blue, red])
    }

    @Test func aDecorationIsStretchedToTheContentAndAligned() {
        let drawn = list(Color.blue.frame(width: 40, height: 20).overlay(alignment: .topLeading) {
            Color.red.frame(width: 10, height: 10)
        })
        let rects = drawn.commands.compactMap { command -> Rect? in
            guard case .shape(let draw) = command else { return nil }
            return Rect(origin: draw.bounds.origin + (draw.origin ?? .zero), size: draw.bounds.size)
        }
        #expect(rects == [Rect(x: 30, y: 40, width: 40, height: 20), Rect(x: 30, y: 40, width: 10, height: 10)])
    }

    @Test func aRotationAndAScaleTurnAboutTheirAnchor() {
        let turned = list(Color.red.frame(width: 20, height: 20).rotationEffect(.degrees(90)))
        let center = Point(x: 50, y: 50)
        #expect(turned.state(at: 0).transform == Transform.identity.concatenating(.around(center, .rotation(.degrees(90)))))

        let scaled = list(Color.red.frame(width: 20, height: 20).scaleEffect(x: 2, y: 3, anchor: .topLeading))
        let corner = Point(x: 40, y: 40)
        #expect(scaled.state(at: 0).transform == Transform.identity.concatenating(.around(corner, .scale(x: 2, y: 3))))
    }
}
