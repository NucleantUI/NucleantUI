//
//  FontFallbackTests.swift
//  NucleantUITests
//
//  #29: a character the bundled Roboto has no glyph for draws in the face
//  the platform falls back to — not as Roboto's missing-glyph box — and is
//  measured as wide as it draws there.
//

import Testing
import NucleantSkia
@testable import NucleantUI

@MainActor
@Suite
struct FontFallbackTests {

    /// A character from each of the issue's lines that drew as a box.
    nonisolated static let missing: [Character] = ["م", "年", "→", "←", "★", "●", "≡", "✓", "▶"]

    let surface = SkSurfaces.raster(width: 100, height: 40)!
    let reference = SkSurfaces.raster(width: 100, height: 40)!
    static let size = 20.0

    private func fallback(for character: Character, _ font: Font = .system(size: size)) -> SkFont? {
        FontFallback.shared.font(
            for: character,
            family: FontRegistry.resolve(font),
            size: font.size,
            bold: font.weight.isBoldFace,
            italic: font.isItalic
        )
    }

    /// Roboto as the renderer draws it.
    private func roboto(_ font: Font = .system(size: size)) -> SkFont? {
        guard let family = FontRegistry.resolve(font), let path = FontRegistry.path(ofResolved: family),
              let face = SkFontMgr.makeFromFile(path) else { return nil }
        let made = SkFont(face, size: Float(font.size * SkiaFonts.pointScale))
        made.setSubpixel(true)
        made.setEdging(.antiAlias)
        made.setHinting(.none)
        return made
    }

    /// `string` drawn by the renderer at (4, 4), a line long.
    private func render(_ string: String) {
        let renderer = SkiaDisplayRenderer(surface: surface)
        var list = DisplayList()
        list.append(.text(TextDraw(
            string: string,
            frame: Rect(x: 4, y: 4, width: 92, height: 32),
            font: .system(size: Self.size),
            color: .init(red: 0, green: 0, blue: 0),
            wraps: false
        )))
        renderer.render(list)
    }

    /// The runs drawn by hand into the reference surface, on the
    /// renderer's first baseline, one after another.
    private func drawReference(_ runs: [(String, SkFont)]) {
        let canvas = reference.getCanvas()
        canvas.clear(SIMD4<Float>(0, 0, 0, 0))
        let paint = SkPaint()
        paint.setColor(SIMD4<UInt8>(0, 0, 0, 255))
        let baseline = 4 + TextMeasurer.lineMetrics(for: .system(size: Self.size)).ascent
        var x = 4.0
        for (text, font) in runs {
            canvas.drawString(text, x: Float(x), y: Float(baseline), font: font, paint: paint)
            x += Double(font.measureText(text))
        }
    }

    /// Every pixel's alpha, row after row.
    private func alphas(_ surface: SkRasterSurface) -> [UInt8] {
        surface.readPixels().enumerated().compactMap { $0.offset % 4 == 3 ? $0.element : nil }
    }

    @Test func aCharacterRobotoHasStaysInRoboto() {
        for character in "Aé …↑↓" {
            #expect(fallback(for: character) == nil, "\(character)")
        }
        #expect(FontFallback.shared.coversASCII(family: FontRegistry.resolve(.system(size: Self.size))))
    }

    @Test(arguments: missing)
    func aCharacterRobotoLacksFallsBackToAFaceThatHasIt(_ character: Character) {
        let font = fallback(for: character)
        #expect(font != nil)
        #expect(font.map { $0.unicharToGlyph(character.unicodeScalars.first!) != 0 } == true)
    }

    @Test(arguments: missing)
    func itIsMeasuredAsWideAsItDraws(_ character: Character) {
        guard let font = fallback(for: character) else {
            Issue.record("no face for \(character)")
            return
        }
        let measured = TextMeasurer.width(of: String(character), font: .system(size: Self.size))
        #expect(measured == Double(font.measureText(String(character))))
    }

    @Test func itDrawsInThatFace() {
        guard let star = fallback(for: "★"), let roboto = roboto() else {
            Issue.record("no faces")
            return
        }
        render("★")
        drawReference([("★", star)])
        let drawn = alphas(surface)
        #expect(drawn.contains { $0 > 0 })
        #expect(drawn == alphas(reference))
        // Not Roboto's missing-glyph box.
        drawReference([("★", roboto)])
        #expect(drawn != alphas(reference))
    }

    @Test func aMixedLineChangesFaceAtEachMissingCharacter() {
        guard let arrow = fallback(for: "→"), let roboto = roboto() else {
            Issue.record("no faces")
            return
        }
        render("ab→cd")
        drawReference([("ab", roboto), ("→", arrow), ("cd", roboto)])
        #expect(alphas(surface) == alphas(reference))
        let font = Font.system(size: Self.size)
        let measured = TextMeasurer.width(of: "ab→cd", font: font)
        let drawn = Double(roboto.measureText("ab")) + Double(arrow.measureText("→")) + Double(roboto.measureText("cd"))
        #expect(abs(measured - drawn) < 0.01)
    }

    @Test func theIssuesLinesHaveAFaceForEveryCharacter() {
        let lines = [
            "Arabic: مرحبا بالعالم",
            "Japanese: 2026年11月11日",
            "Arrows: → ← ↑ ↓",
            "Symbols: ★ ● ≡ ✓ ▶",
        ]
        let font = Font.system(size: Self.size)
        guard let family = FontRegistry.resolve(font), let path = FontRegistry.path(ofResolved: family),
              let face = SkFontMgr.makeFromFile(path) else {
            Issue.record("no Roboto")
            return
        }
        for line in lines {
            for character in line {
                let scalar = character.unicodeScalars.first!
                let shown = face.unicharToGlyph(scalar) != 0 || fallback(for: character) != nil
                #expect(shown, "\(character) in \(line)")
            }
        }
    }
}
