//
//  TextMeasurer.swift
//  NucleantUI
//
//  Text sizing, done through ThorVG's own font metrics so layout and drawing
//  agree. Widths come from summing per-glyph advances
//  (`tvg_text_get_glyph_metrics`) rather than from a paint's AABB: the AABB is
//  only valid once a canvas has updated the paint, and layout runs before
//  anything is on a canvas.
//

import NucleantThorVG

@MainActor
enum TextMeasurer {

    /// Identifies one resolved face+size — what the face table is keyed on.
    private struct FaceKey: Hashable {
        let family: String?
        let size: Double
        let italic: Bool
    }

    /// Everything measured for one face, filled in as it is asked for.
    /// Faces are looked up once per call and then addressed by index, so a
    /// glyph's advance is an array read rather than a hash of the face's
    /// family name and the character.
    private struct Face {
        let key: FaceKey
        /// One reusable `Tvg_Paint`, so measuring a string doesn't allocate a
        /// text object per call. Never added to a canvas — released only
        /// when the process ends, which is the same lifetime as the table.
        var probe: Tvg_Paint?
        var hasProbe = false
        /// Advances of the single-byte ASCII characters, by code; NaN until
        /// measured.
        var ascii = [Double](repeating: .nan, count: 128)
        /// Advances of every other character.
        var other: [Character: Double] = [:]
        var lineMetrics: (ascent: Double, descent: Double, lineHeight: Double)?
    }

    private static var faces: [Face] = []
    private static var faceIndices: [FaceKey: Int] = [:]

    private static func face(for font: Font) -> Int {
        if PerfTrace.isEnabled { PerfTrace.textMeasures += 1 }
        let key = FaceKey(family: FontRegistry.resolve(font), size: font.size, italic: font.isItalic)
        if let index = faceIndices[key] { return index }
        faces.append(Face(key: key))
        faceIndices[key] = faces.count - 1
        return faces.count - 1
    }

    private static func probe(_ face: Int) -> Tvg_Paint? {
        if faces[face].hasProbe { return faces[face].probe }
        faces[face].hasProbe = true
        ThorEngine.ensureInitialized()
        guard let paint = tvg_text_new() else { return nil }
        let key = faces[face].key
        if let family = key.family {
            _ = family.withCString { tvg_text_set_font(paint, $0) }
        } else {
            _ = tvg_text_set_font(paint, nil)
        }
        _ = tvg_text_set_size(paint, Float(key.size))
        faces[face].probe = paint
        return paint
    }

    /// Ascent / descent / line height for a font, in points.
    static func lineMetrics(for font: Font) -> (ascent: Double, descent: Double, lineHeight: Double) {
        lineMetrics(face: face(for: font))
    }

    private static func lineMetrics(face: Int) -> (ascent: Double, descent: Double, lineHeight: Double) {
        if let cached = faces[face].lineMetrics { return cached }

        let size = faces[face].key.size
        var result = (ascent: size * 0.8, descent: size * 0.2, lineHeight: size * 1.2)
        if let paint = probe(face) {
            var metrics = Tvg_Text_Metrics()
            if tvg_text_get_text_metrics(paint, &metrics) == TVG_RESULT_SUCCESS, metrics.advance > 0 {
                result = (
                    ascent: Double(metrics.ascent),
                    descent: Double(-metrics.descent),
                    lineHeight: Double(metrics.advance)
                )
            }
        }
        faces[face].lineMetrics = result
        return result
    }

    /// The advance width of one character, in points.
    @inline(__always)
    private static func advance(_ character: Character, face: Int) -> Double {
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
        // Fallback ratio for a face ThorVG can't measure — roughly the average
        // advance of a proportional Latin face at a given em size.
        var width = faces[face].key.size * 0.5
        if let paint = probe(face) {
            var metrics = Tvg_Glyph_Metrics()
            let result = String(character).withCString {
                tvg_text_get_glyph_metrics(paint, $0, &metrics)
            }
            if result == TVG_RESULT_SUCCESS, metrics.advance > 0 {
                width = Double(metrics.advance)
            }
        }
        return width
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
    private static func width<S: StringProtocol>(of characters: S, face: Int, from start: Double = 0) -> Double {
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
    private static func paragraphs(of string: String) -> [String] {
        string.utf8.contains(0x0A) ? string.components(separatedBy: "\n") : [string]
    }

    /// The width of `string` on a single line.
    static func width(of string: String, font: Font) -> Double {
        width(of: string, face: face(for: font))
    }

    /// Break `string` into lines that fit `maxWidth`, at word boundaries where
    /// possible. `maxWidth == nil` means one line, however long.
    static func wrap(_ string: String, font: Font, maxWidth: Double?, lineLimit: Int?) -> [String] {
        let paragraphs = Self.paragraphs(of: string)
        guard let maxWidth, maxWidth > 0 else {
            return limited(paragraphs, to: lineLimit)
        }

        let face = Self.face(for: font)
        var lines: [String] = []

        for paragraph in paragraphs {
            breakLines(paragraph, face: face, maxWidth: maxWidth) { line in
                lines.append(String(paragraph[line]))
            }
        }
        return limited(lines, to: lineLimit)
    }

    /// The lines `paragraph` breaks into at `maxWidth`, handed to `line` in
    /// order as ranges of it — word by word, a line's words joined by the
    /// single spaces between them; a line that is still empty takes a word
    /// without the space before it.
    ///
    /// Each line is a range rather than a string built a word at a time, so
    /// breaking costs one walk of the characters and no allocation. The sums
    /// are taken in the same order as summing the advances of the joined
    /// string, so a line breaks exactly where it would.
    private static func breakLines(
        _ paragraph: String,
        face: Int,
        maxWidth: Double,
        _ line: (Range<String.Index>) -> Void
    ) {
        let space = advance(" ", face: face)
        var lineStart = paragraph.startIndex
        var lineEnd = paragraph.startIndex
        var currentWidth = 0.0

        for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
            let isEmpty = lineStart == lineEnd
            let pieceWidth = isEmpty ? width(of: word, face: face) : width(of: word, face: face, from: space)
            if !isEmpty && currentWidth + pieceWidth > maxWidth {
                line(lineStart..<lineEnd)
                lineStart = word.startIndex
                lineEnd = word.endIndex
                currentWidth = width(of: word, face: face)
            } else {
                if isEmpty { lineStart = word.startIndex }
                lineEnd = word.endIndex
                currentWidth += pieceWidth
            }
        }
        line(lineStart..<lineEnd)
    }

    private static func limited(_ lines: [String], to lineLimit: Int?) -> [String] {
        guard let lineLimit, lineLimit > 0, lines.count > lineLimit else { return lines }
        return Array(lines.prefix(lineLimit))
    }

    /// Measured boxes, keyed by everything that decides one. Text sizing is
    /// the leaf of every layout pass and by far its most expensive step, so it
    /// is worth remembering across passes as well as within one — the same
    /// label re-measured after a state change has not changed shape.
    private struct SizeKey: Hashable {
        let string: String
        let font: Font
        let proposal: ProposedSize
        let lineLimit: Int?
    }

    private static var sizes: [SizeKey: Size] = [:]

    /// The box `string` occupies under `proposal`.
    static func size(of string: String, font: Font, proposal: ProposedSize, lineLimit: Int?) -> Size {
        let key = SizeKey(string: string, font: font, proposal: proposal, lineLimit: lineLimit)
        if let cached = sizes[key] { return cached }
        let measured = measure(key)
        // A miss only: a long-running app showing ever-new strings (a
        // clock, a counter) would otherwise keep every one it ever showed.
        if sizes.count >= 4096 { sizes.removeAll(keepingCapacity: true) }
        sizes[key] = measured
        return measured
    }

    /// The lines `wrap` would give, measured where they stand in the string
    /// rather than built: how many there are, and the widest.
    private static func measure(_ key: SizeKey) -> Size {
        let (string, font, proposal, lineLimit) = (key.string, key.font, key.proposal, key.lineLimit)
        let face = Self.face(for: font)
        guard !string.isEmpty else {
            return Size(width: 0, height: lineMetrics(face: face).lineHeight)
        }
        let limit = lineLimit.flatMap { $0 > 0 ? $0 : nil } ?? .max
        var widest = 0.0
        var count = 0

        let paragraphs = Self.paragraphs(of: string)
        if let maxWidth = proposal.width, maxWidth > 0 {
            for paragraph in paragraphs where count < limit {
                breakLines(paragraph, face: face, maxWidth: maxWidth) { line in
                    guard count < limit else { return }
                    widest = max(widest, width(of: paragraph[line], face: face))
                    count += 1
                }
            }
        } else {
            for paragraph in paragraphs.prefix(limit) {
                widest = max(widest, width(of: paragraph, face: face))
                count += 1
            }
        }

        let lineHeight = lineMetrics(face: face).lineHeight
        return Size(
            width: proposal.width.map { min(widest, $0) } ?? widest,
            height: lineHeight * Double(count)
        )
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
