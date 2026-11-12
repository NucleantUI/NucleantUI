//
//  FontFallback.swift
//  NucleantUI
//
//  The faces text falls back to for the characters its own face has no
//  glyph for — Arabic, CJK, arrows, symbols, against the bundled Roboto —
//  asked of the platform's font manager through Skia, which draws the text:
//  CoreText on Apple platforms, fontconfig on Linux, the system font set on
//  Android. The measurer and the renderer ask the same faces for the same
//  characters, so a line is laid out as wide as it draws.
//

import NucleantSkia

@MainActor
final class FontFallback {

    /// The one the measurer and every renderer ask, so a character falls
    /// back to the same face wherever it is measured or drawn.
    static let shared = FontFallback()

    /// The face each family `FontRegistry` resolved draws in, asked only
    /// which glyphs it has; `nil` is the platform's default face.
    private var primaries: [String?: SkTypeface] = [:]
    /// Whether a family's face has every printable ASCII character — a line
    /// of nothing else then draws in it whole, without a look at each.
    private var asciiCoverage: [String?: Bool] = [:]

    private struct Miss: Hashable {
        let bold: Bool
        let italic: Bool
        let scalar: Unicode.Scalar
    }
    /// The face found for each character missed, by the first of its
    /// scalars the family's face lacks: an index into `found`, `nil` when no
    /// face has it.
    private var misses: [Miss: Int?] = [:]
    /// Every face fallen back to, once each — one face covers many
    /// characters, and the fonts made from it are shared between them.
    private var found: [SkTypeface] = []
    private var foundIndices: [String: Int] = [:]

    private struct FontKey: Hashable {
        let face: Int
        let size: Double
        let slanted: Bool
    }
    private var fonts: [FontKey: SkFont] = [:]

    /// The font `character` draws in when `family`'s face has no glyph for
    /// it: the platform's face for it, at `size` points, as bold and italic
    /// as asked. `nil` when the family's face has it — or when no face does,
    /// and it shows as the face's own missing-glyph box.
    func font(for character: Character, family: String?, size: Double, bold: Bool, italic: Bool) -> SkFont? {
        guard let primary = primary(for: family), let scalar = missing(character, in: primary) else { return nil }
        let miss = Miss(bold: bold, italic: italic, scalar: scalar)
        let face: Int
        if let cached = misses[miss] {
            guard let cached else { return nil }
            face = cached
        } else {
            let index = search(miss)
            // Filed even when nil — a character no face has is not searched
            // for again.
            misses.updateValue(index, forKey: miss)
            guard let index else { return nil }
            face = index
        }
        // No italic face for it: a synthetic shear still reads as italic.
        let slanted = italic && !found[face].isItalic()
        let key = FontKey(face: face, size: size, slanted: slanted)
        if let font = fonts[key] { return font }
        let font = SkFont(found[face], size: Float(size * SkiaDisplayRenderer.thorPointScale))
        font.setSubpixel(true)
        font.setEdging(.antiAlias)
        // Unhinted, as the family's own font is drawn and measured.
        font.setHinting(.none)
        if slanted { font.setSkewX(-0.2) }
        fonts[key] = font
        return font
    }

    /// Whether `family`'s face has every printable ASCII character, so a
    /// line of nothing else needs no fallback.
    func coversASCII(family: String?) -> Bool {
        if let covered = asciiCoverage[family] { return covered }
        let covered = primary(for: family).map { face in
            (0x20...0x7E).allSatisfy { face.unicharToGlyph(Unicode.Scalar(UInt8($0))) != 0 }
        } ?? true
        asciiCoverage[family] = covered
        return covered
    }

    /// The face `family` draws in: the file `FontRegistry` loaded it from,
    /// else the platform's default face — as the renderer picks it.
    private func primary(for family: String?) -> SkTypeface? {
        if let face = primaries[family] { return face }
        var face: SkTypeface?
        if let family, let path = FontRegistry.path(ofResolved: family) {
            face = SkFontMgr.makeFromFile(path)
        }
        if face == nil { face = SkFontMgr.matchFamilyStyle(nil) }
        primaries[family] = face
        return face
    }

    /// The first of `character`'s scalars `face` has no glyph for. Controls
    /// and the scalars that draw nothing — joiners, variation selectors —
    /// never send a character elsewhere.
    private func missing(_ character: Character, in face: SkTypeface) -> Unicode.Scalar? {
        character.unicodeScalars.first { scalar in
            let properties = scalar.properties
            return properties.generalCategory != .control
                && !properties.isDefaultIgnorableCodePoint
                && face.unicharToGlyph(scalar) == 0
        }
    }

    /// The platform's face nearest the style asked for with a glyph for the
    /// scalar missed, filed once by its family and style.
    private func search(_ miss: Miss) -> Int? {
        let style = SkFontStyle(weight: miss.bold ? 700 : 400, slant: miss.italic ? .italic : .upright)
        guard let face = SkFontMgr.matchFamilyStyleCharacter(nil, style: style, character: miss.scalar),
              face.unicharToGlyph(miss.scalar) != 0
        else { return nil }
        let faceStyle = face.fontStyle()
        let name = "\(face.getFamilyName()) \(faceStyle.weight) \(faceStyle.width) \(faceStyle.slant.rawValue)"
        if let index = foundIndices[name] { return index }
        found.append(face)
        foundIndices[name] = found.count - 1
        return found.count - 1
    }
}
