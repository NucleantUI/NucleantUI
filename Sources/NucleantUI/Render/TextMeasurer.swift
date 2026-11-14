//
//  TextMeasurer.swift
//  NucleantUI
//
//  Text sizing, done with the very Skia font the text is drawn with
//  (`SkiaFonts`), so layout and drawing agree. Widths come from summing
//  per-glyph advances, line heights from the font's metrics. A character the
//  face has no glyph for is measured in the face it falls back to
//  (`FontFallback`), which is the face it draws in.
//

import NucleantSkia
import NucleantThorVG

/// The Skia faces and fonts text is measured and drawn with: one face per
/// family `FontRegistry` resolved, from the file it resolved, and one font
/// per face, size and synthetic slant. `TextMeasurer` and
/// `SkiaDisplayRenderer` take theirs from here, so a text is measured with
/// the font that draws it.
@MainActor
final class SkiaFonts {
    static let shared = SkiaFonts()

    /// A text size is points at 96 DPI, drawn `size × 96/72` units tall —
    /// the size the text boxes of every view are made for; Skia's size is
    /// the em height itself, so it is given the factor.
    static let pointScale = 96.0 / 72.0

    private struct Key: Hashable {
        let family: String?
        let size: Double
        let slanted: Bool
    }

    private var fonts: [Key: SkFont] = [:]
    /// Faces loaded into Skia, by the family name `FontRegistry` resolved.
    private var typefaces: [String: SkTypeface] = [:]
    /// The platform's default face, for a font nothing resolved for.
    private var defaultTypeface: SkTypeface?

    private init() {}

    /// The font for `family` at `size` points — sheared, `slanted`, where
    /// there is no italic face.
    func font(family: String?, size: Double, slanted: Bool) -> SkFont {
        let key = Key(family: family, size: size, slanted: slanted)
        if let font = fonts[key] { return font }
        let font = SkFont(typeface(for: family), size: Float(size * Self.pointScale))
        font.setSubpixel(true)
        font.setEdging(.antiAlias)
        // Unhinted. Where Skia reads glyphs through FreeType (the browser,
        // Linux, Android) its default hinting rounds every advance to a
        // whole pixel, and a word drifts off its measured width a pixel
        // every few letters.
        font.setHinting(.none)
        if slanted { font.setSkewX(-0.2) }
        fonts[key] = font
        return font
    }

    /// The font `font` draws with, resolved.
    func font(for font: Font) -> SkFont {
        let family = FontRegistry.resolve(font)
        return self.font(family: family, size: font.size, slanted: Self.isSlanted(font, family: family))
    }

    /// Whether `font` is drawn sheared: italic with no italic face found.
    static func isSlanted(_ font: Font, family: String?) -> Bool {
        font.isItalic && !(family?.contains("Italic") ?? false)
    }

    private func typeface(for family: String?) -> SkTypeface? {
        if let family {
            if let loaded = typefaces[family] { return loaded }
            if let path = FontRegistry.path(ofResolved: family), let made = SkFontMgr.makeFromFile(path) {
                typefaces[family] = made
                return made
            }
        }
        if defaultTypeface == nil {
            defaultTypeface = SkFontMgr.matchFamilyStyle(nil)
        }
        return defaultTypeface
    }
}

@MainActor
enum TextMeasurer {

    /// Identifies one resolved face+size — what the face table is keyed on.
    private struct FaceKey: Hashable {
        let family: String?
        let size: Double
        let bold: Bool
        let italic: Bool
        /// Points added to every advance: kerning or tracking. A face with
        /// spacing has its own table, so every width summed from it —
        /// breaking lines, cutting one — has the spacing in it.
        let spacing: Double
    }

    /// Everything measured for one face, filled in as it is asked for.
    /// Faces are looked up once per call and then addressed by index, so a
    /// glyph's advance is an array read rather than a hash of the face's
    /// family name and the character.
    private struct Face {
        let key: FaceKey
        /// The font it draws with, made the first time it is measured.
        var font: SkFont?
        /// Advances of the single-byte ASCII characters, by code; NaN until
        /// measured.
        var ascii = [Double](repeating: .nan, count: 128)
        /// Advances of every other character.
        var other: [Character: Double] = [:]
        var lineMetrics: (ascent: Double, descent: Double, lineHeight: Double)?
    }

    private static var faces: [Face] = []
    private static var faceIndices: [FaceKey: Int] = [:]

    static func face(for font: Font, spacing: Double = 0) -> Int {
        if PerfTrace.isEnabled { PerfTrace.textMeasures += 1 }
        let key = FaceKey(
            family: FontRegistry.resolve(font),
            size: font.size,
            bold: font.weight.isBoldFace,
            italic: font.isItalic,
            spacing: spacing
        )
        if let index = faceIndices[key] { return index }
        faces.append(Face(key: key))
        faceIndices[key] = faces.count - 1
        return faces.count - 1
    }

    private static func font(_ face: Int) -> SkFont {
        if let font = faces[face].font { return font }
        let key = faces[face].key
        let slanted = key.italic && !(key.family?.contains("Italic") ?? false)
        let font = SkiaFonts.shared.font(family: key.family, size: key.size, slanted: slanted)
        faces[face].font = font
        return font
    }

    /// Ascent / descent / line height for a font, in points.
    static func lineMetrics(for font: Font) -> (ascent: Double, descent: Double, lineHeight: Double) {
        lineMetrics(face: face(for: font))
    }

    static func lineMetrics(face: Int) -> (ascent: Double, descent: Double, lineHeight: Double) {
        if let cached = faces[face].lineMetrics { return cached }

        let size = faces[face].key.size
        var result = (ascent: size * 0.8, descent: size * 0.2, lineHeight: size * 1.2)
        let metrics = font(face).getMetrics()
        let lineHeight = Double(metrics.descent - metrics.ascent + metrics.leading)
        if lineHeight > 0 {
            result = (ascent: Double(-metrics.ascent), descent: Double(metrics.descent), lineHeight: lineHeight)
        }
        faces[face].lineMetrics = result
        return result
    }

    /// The advance width of one character, in points.
    @inline(__always)
    static func advance(_ character: Character, face: Int) -> Double {
        // `"\r\n"` is one character whose `asciiValue` is that of `"\n"`;
        // it goes the long way, as anything else that isn't one ASCII byte.
        if let code = character.asciiValue, code != 0x0A || character.utf8.count == 1 {
            let cached = faces[face].ascii[Int(code)]
            if !cached.isNaN { return cached }
            let width = measureAdvance(character, face: face)
            faces[face].ascii[Int(code)] = width
            return width
        }
        if let cached = faces[face].other[character] { return cached }
        let width = measureAdvance(character, face: face)
        faces[face].other[character] = width
        return width
    }

    private static func measureAdvance(_ character: Character, face: Int) -> Double {
        let key = faces[face].key
        // A character the face has no glyph for draws in the face the
        // platform falls back to for it, and is as wide as it is there.
        if let fallback = FontFallback.shared.font(
            for: character, family: key.family, size: key.size, bold: key.bold, italic: key.italic
        ) {
            return Double(fallback.measureText(String(character))) + key.spacing
        }
        let skiaFont = font(face)
        let measured = Double(skiaFont.getWidths(skiaFont.textToGlyphs(String(character))).reduce(0, +))
        // A face with nothing to say about it: roughly the average advance
        // of a proportional Latin face at a given em size.
        let width = measured > 0 || character.isWhitespace && character != " " ? measured : faces[face].key.size * 0.5
        return width + faces[face].key.spacing
    }

    /// The summed advances of `characters`, starting from `start`, added in
    /// order.
    ///
    /// ASCII is read a byte at a time: two ASCII characters side by side are
    /// always two characters, unless they are CR and LF. Each byte's advance
    /// is held back until the next byte shows it ends a character; at the
    /// first byte that doesn't — anything outside ASCII, which may combine
    /// with the character before it, or a CR — the rest is walked a
    /// character at a time from the start of the character held back. A
    /// character the ASCII table doesn't have yet goes through `advance`,
    /// which measures and files it.
    static func width<S: StringProtocol>(of characters: S, face: Int, from start: Double = 0) -> Double {
        let ascii = faces[face].ascii
        var width = start
        let utf8 = characters.utf8
        var index = utf8.startIndex
        var held: (start: String.Index, advance: Double)?
        while index != utf8.endIndex {
            let byte = utf8[index]
            guard byte < 0x80, byte != 0x0D else { break }
            let advance = ascii[Int(byte)]
            guard !advance.isNaN else { break }
            if let held { width += held.advance }
            held = (index, advance)
            utf8.formIndex(after: &index)
        }
        guard index != utf8.endIndex else { return width + (held?.advance ?? 0) }

        for character in characters[(held?.start ?? index)...] {
            if let code = character.asciiValue, code != 0x0A || character.utf8.count == 1 {
                let cached = ascii[Int(code)]
                if !cached.isNaN {
                    width += cached
                    continue
                }
            }
            width += advance(character, face: face)
        }
        return width
    }

    /// `string` split at its line feeds, as `components(separatedBy:)`
    /// splits it — without the trip through Foundation for the usual string
    /// that has none.
    static func paragraphs(of string: String) -> [String] {
        string.utf8.contains(0x0A) ? string.components(separatedBy: "\n") : [string]
    }

    /// The width of `string` on a single line.
    static func width(of string: String, font: Font) -> Double {
        width(of: string, face: face(for: font))
    }

    /// Break `string` into lines that fit `maxWidth`, at word boundaries where
    /// possible. `maxWidth == nil` or infinite means a line a paragraph,
    /// however long; 0 means as narrow as the text goes.
    static func wrap(_ string: String, font: Font, maxWidth: Double?, lineLimit: Int?) -> [String] {
        let paragraphs = Self.paragraphs(of: string)
        guard let maxWidth, maxWidth < .infinity else {
            return limited(paragraphs, to: lineLimit)
        }
        let room = max(maxWidth, 0)

        let face = Self.face(for: font)
        var lines: [String] = []

        for paragraph in paragraphs {
            breakLines(paragraph, face: face, maxWidth: room) { line in
                lines.append(String(paragraph[line]))
            }
        }
        return limited(lines, to: lineLimit)
    }

    /// The lines `paragraph` breaks into at `maxWidth`, handed to `line` in
    /// order as ranges of it — word by word, a line's words joined by the
    /// single spaces between them.
    ///
    /// The paragraph's first line keeps the spaces it starts with: they are
    /// its indent. When the first word doesn't fit after them, the indent
    /// is a line of its own. A line begun by a break takes its first word
    /// without the spaces before it, which are where the line before ended.
    ///
    /// Inside a word, a line may also end after a hyphen, a slash or a dash
    /// (`breaksAfter`), so a word that doesn't fit the rest of a line puts
    /// as much of itself there as fits up to one of those, and the rest
    /// starts the next line. What is too wide for a line of its own — a
    /// URL, a path, an identifier — goes the same way, and where there's no
    /// such place it is broken between characters: as many as fit, and
    /// never none, so a character wider than the line still gets one. The
    /// last piece of a word starts the line the words after it go on.
    ///
    /// Each line is a range rather than a string built a word at a time, so
    /// breaking costs one walk of the characters and no allocation. The sums
    /// are taken in the same order as summing the advances of the joined
    /// string, so a line breaks exactly where it would.
    static func breakLines(
        _ paragraph: String,
        face: Int,
        maxWidth: Double,
        _ line: (Range<String.Index>) -> Void
    ) {
        let space = advance(" ", face: face)
        var lineStart = paragraph.startIndex
        var lineEnd = paragraph.startIndex
        var currentWidth = 0.0
        // Until the paragraph's first word, the line is its indent.
        var inIndent = true

        for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
            if inIndent {
                if word.startIndex == paragraph.startIndex {
                    // The paragraph's first piece, with no space before it.
                    guard !word.isEmpty else { continue }
                    inIndent = false
                    startLine(word, of: word, face: face, maxWidth: maxWidth, &lineStart, &lineEnd, &currentWidth, line)
                    continue
                }
                if word.isEmpty {
                    // Another space of the indent, kept however wide.
                    lineEnd = word.endIndex
                    currentWidth += space
                    continue
                }
                // The first word goes after the indent as after a word.
                inIndent = false
            } else if lineStart == lineEnd {
                // A run of spaces at a break leaves the line empty, so the
                // next word starts it again.
                startLine(word, of: word, face: face, maxWidth: maxWidth, &lineStart, &lineEnd, &currentWidth, line)
                continue
            }
            let pieceWidth = width(of: word, face: face, from: space)
            if currentWidth + pieceWidth <= maxWidth {
                lineEnd = word.endIndex
                currentWidth += pieceWidth
            } else {
                endLine(within: word, face: face, maxWidth: maxWidth, space: space, &lineStart, &lineEnd, &currentWidth, line)
            }
        }
        line(lineStart..<lineEnd)
    }

    /// The line, with no room left for all of `word` after a space, ended
    /// as late in `word` as fits where it may break, or before it when no
    /// such place fits; what is left of `word` starts the next line.
    private static func endLine(
        within word: Substring,
        face: Int,
        maxWidth: Double,
        space: Double,
        _ lineStart: inout String.Index,
        _ lineEnd: inout String.Index,
        _ currentWidth: inout Double,
        _ line: (Range<String.Index>) -> Void
    ) {
        // Most words have nowhere to break, which their bytes show without
        // walking their characters: no hyphen, no slash, and nothing from
        // U+2000–U+2FFF, where the dashes are.
        guard word.utf8.contains(where: { $0 == 0x2D || $0 == 0x2F || $0 == 0xE2 }) else {
            line(lineStart..<lineEnd)
            startLine(word, of: word, face: face, maxWidth: maxWidth, &lineStart, &lineEnd, &currentWidth, line)
            return
        }
        var sum = space
        var cut: String.Index?
        var index = word.startIndex
        while index != word.endIndex {
            let character = word[index]
            sum += advance(character, face: face)
            if currentWidth + sum > maxWidth { break }
            let next = word.index(after: index)
            if index != word.startIndex, next != word.endIndex, breaksAfter(character, before: word[next]) {
                cut = next
            }
            index = next
        }
        if let cut {
            line(lineStart..<cut)
            startLine(word[cut...], of: word, face: face, maxWidth: maxWidth, &lineStart, &lineEnd, &currentWidth, line)
        } else {
            line(lineStart..<lineEnd)
            startLine(word, of: word, face: face, maxWidth: maxWidth, &lineStart, &lineEnd, &currentWidth, line)
        }
    }

    /// `rest`, the end of `word`, starting a line: on it whole when it
    /// fits, and otherwise over as many lines as it takes, each ending at
    /// the last place before the character that overflows it where the
    /// word may break, or right before that character when there's none.
    private static func startLine(
        _ rest: Substring,
        of word: Substring,
        face: Int,
        maxWidth: Double,
        _ lineStart: inout String.Index,
        _ lineEnd: inout String.Index,
        _ currentWidth: inout Double,
        _ line: (Range<String.Index>) -> Void
    ) {
        lineStart = rest.startIndex
        lineEnd = rest.endIndex
        currentWidth = width(of: rest, face: face)
        guard currentWidth > maxWidth else { return }

        var sum = 0.0
        var cut: String.Index?
        var index = rest.startIndex
        while index != rest.endIndex {
            let character = rest[index]
            let step = advance(character, face: face)
            if index != lineStart, sum + step > maxWidth, let at = cut {
                line(lineStart..<at)
                lineStart = at
                sum = width(of: rest[at..<index], face: face)
                cut = nil
            }
            if index != lineStart, sum + step > maxWidth {
                line(lineStart..<index)
                lineStart = index
                sum = 0
            }
            sum += step
            let next = rest.index(after: index)
            if index != word.startIndex, next != rest.endIndex, breaksAfter(character, before: rest[next]) {
                cut = next
            }
            index = next
        }
        currentWidth = sum
    }

    /// Whether a line may end between `character` and `next` inside a word,
    /// as Unicode line breaking allows: after a hyphen, a slash, or a dash —
    /// though not when it is the word's first character, which is what
    /// `breakLines` checks. Not before a digit after a hyphen or slash, which
    /// read as one with it ("-3", "1/2"), and not before closing punctuation,
    /// quotation marks, an ellipsis, or another hyphen, slash or dash.
    static func breaksAfter(_ character: Character, before next: Character) -> Bool {
        switch character {
        case "-", "/":
            if next.unicodeScalars.first?.properties.numericType == .decimal { return false }
        case "\u{2010}", "\u{2012}", "\u{2013}", "\u{2014}":
            break
        default:
            return false
        }
        switch next {
        case ")", "]", "}", "!", "?", ",", ".", ":", ";", "\"", "'", "\u{2026}",
             "-", "/", "\u{2010}", "\u{2012}", "\u{2013}", "\u{2014}":
            return false
        default:
            return true
        }
    }

    private static func limited(_ lines: [String], to lineLimit: Int?) -> [String] {
        guard let lineLimit, lineLimit > 0, lines.count > lineLimit else { return lines }
        return Array(lines.prefix(lineLimit))
    }
}

/// ThorVG's process-wide engine.
///
/// Nothing ThorVG-side works until this has run: `tvg_wgcanvas_create` returns
/// null, and text can't be measured because the font loader isn't up. The app
/// runtime calls it at launch; the calls from the renderer and the measurer are
/// a backstop for a `ViewHost` driven without `NucleantApp` (an embedded host,
/// a test).
///
/// The thread count is fixed by the *first* call and ignored afterwards — which
/// is why the app runtime's call, made before any other, is the one that
/// decides it.
@MainActor
public enum ThorEngine {
    private static var initialized = false

    public static func ensureInitialized(threads: UInt32 = 0) {
        guard !initialized else { return }
        initialized = true
        _ = tvg_engine_init(threads)
    }
}
