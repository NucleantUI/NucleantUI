//
//  ColorTests.swift
//  NucleantUITests
//
//  `Color` is a `SIMD` vector of four `Float`s and nothing else: 16 bytes
//  that are red, green, blue and alpha in that order, so its memory is the
//  `vec4` a shader reads. Light and dark live in `ShapeStyle.dynamic`.
//

import Testing
@testable import NucleantUI

struct ColorVector {

    @Test
    func aColorIsSixteenBytesOfFourFloats() {
        #expect(MemoryLayout<Color>.size == 16)
        #expect(MemoryLayout<Color>.stride == 16)
        let color = Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        let floats = withUnsafeBytes(of: color) { Array($0.bindMemory(to: Float.self)) }
        #expect(floats == [0.1, 0.2, 0.3, 0.4])
    }

    @Test
    func theLanesAreRedGreenBlueAlpha() {
        var color = Color(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.4)
        #expect(color.scalarCount == 4)
        #expect((0..<4).map { color[$0] } == [0.1, 0.2, 0.3, 0.4])
        color[2] = 0.9
        #expect(color.blue == 0.9)
        #expect(Color() == .clear)
    }

    @Test
    func anArrayLiteralIsRedGreenBlueAlpha() {
        let color: Color = [1, 0.5, 0, 0.25]
        #expect(color == Color(red: 1, green: 0.5, blue: 0, opacity: 0.25))
    }

    @Test
    func colorMathIsVectorMath() {
        let a = Color(red: 0, green: 0.5, blue: 1, opacity: 1)
        let b = Color(red: 1, green: 1, blue: 0, opacity: 0.5)
        #expect(a + (b - a) * 0.5 == Color(red: 0.5, green: 0.75, blue: 0.5, opacity: 0.75))
        #expect((a * 2).clamped(lowerBound: .zero, upperBound: .one) == Color(red: 0, green: 1, blue: 1, opacity: 1))
    }

    @Test
    func opacityFadesAlpha() {
        #expect(Color(white: 0.2, opacity: 0.5).opacity(0.5) == Color(white: 0.2, opacity: 0.25))
    }

    /// Every 8-bit hex channel comes back out of `rgba8` as itself.
    @Test
    func hexChannelsRoundTripThroughRGBA8() {
        for value in UInt32(0)...255 {
            let (r, g, b, a) = Color(hex: value << 16 | (255 - value) << 8 | value).rgba8
            #expect([r, g, b, a] == [UInt8(value), UInt8(255 - value), UInt8(value), 255])
        }
        let (r, g, b, a) = Color(red: -1, green: 2, blue: 0.5, opacity: 1).rgba8
        #expect([r, g, b, a] == [0, 255, 127, 255])
    }
}

struct DynamicShapeStyle {

    @Test
    func aDynamicStyleResolvesToTheSchemesColor() {
        let style = ShapeStyle.dynamic(light: Color(white: 0.2), dark: Color(white: 0.8))
        #expect(style.resolved(for: .light) == .color(Color(white: 0.2)))
        #expect(style.resolved(for: .dark) == .color(Color(white: 0.8)))
        #expect(ShapeStyle.color(.red).resolved(for: .dark) == .color(.red))
    }

    @Test
    func opacityFadesBothAppearances() {
        let faded = ShapeStyle.dynamic(light: Color(white: 0.2), dark: Color(white: 0.8, opacity: 0.5)).opacity(0.5)
        #expect(faded == .dynamic(light: Color(white: 0.2, opacity: 0.5), dark: Color(white: 0.8, opacity: 0.25)))
    }

    /// The draw context picks the scheme's color and fades it by the
    /// inherited opacity.
    @Test
    func theDrawContextResolvesForItsScheme() {
        var context = DrawContext(colorScheme: .dark)
        context.opacity = 0.5
        let style = ShapeStyle.dynamic(light: Color(white: 0.2), dark: Color(white: 0.8))
        #expect(context.resolve(style) == .color(Color(white: 0.8, opacity: 0.5)))
    }

    /// A flat color and a dynamic one animate into each other: both carry
    /// both appearances.
    @Test
    func aStyleAnimatesAsBothAppearances() {
        let style = ShapeStyle.dynamic(light: Color(white: 0.25), dark: Color(white: 0.75))
        #expect(style.animatableVector == [0.25, 0.25, 0.25, 1, 0.75, 0.75, 0.75, 1])
        #expect(ShapeStyle(animatableVector: style.animatableVector) == style)
        #expect(ShapeStyle(animatableVector: ShapeStyle.color(.white).animatableVector) == .color(.white))
    }
}
