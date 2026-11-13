//
//  TextLayout.swift
//  NucleantUI
//
//  A `Text`'s lines under one proposal. The text breaks by word into as
//  many lines as the line limit and the height leave room for, never fewer
//  than one. The last line shown takes the rest of the text: it is drawn
//  whole if it fits, tightened if that is allowed and enough, and otherwise
//  cut with an ellipsis at its head, middle or tail. With a
//  `minimumScaleFactor`, the whole text is first set smaller until nothing
//  is cut. Each text keeps the few layouts it was last asked for, and one
//  layout answers every proposal between its own and the size it gave.
//

/// The paragraph settings a `Text` is laid out with, read from the
/// environment in one go.
struct TextParagraphStyle: Hashable {
    /// The most lines shown; `nil` for as many as the text has. Zero and
    /// below are one line.
    var lineLimit: Int? = nil
    /// The lines the text keeps room for, however few it has.
    var reservedLines = 0
    var truncationMode = Text.TruncationMode.tail
    /// Between the bottom of one line and the top of the next; below 0 is 0.
    var lineSpacing = 0.0
    var allowsTightening = false
    /// The smallest fraction of its font size the text may be set at to
    /// fit; 1 to never shrink.
    var minimumScaleFactor = 1.0
}

/// Everything that decides a text's lines other than the proposal: what
/// its layouts are kept by.
struct TextLayoutInput: Hashable {
    var string: String
    var font: Font
    /// Points added after every character: the tracking, or else the
    /// kerning.
    var letterSpacing = 0.0
    /// How far the glyphs are moved up (below 0, down). The box grows by as
    /// much, on the side they moved away from.
    var baselineOffset = 0.0
    var paragraph = TextParagraphStyle()
}

/// A text laid out under one proposal.
struct TextLayout: Equatable {
    /// The lines as they are drawn; one that was cut carries its "…".
    var lines: [String]
    var size: Size
    /// What the font size is multiplied by: below 1 when the text was set
    /// smaller to fit.
    var scale = 1.0
    /// Space added after each character of the last line: below 0 when it
    /// was tightened to fit.
    var lastLineTightening = 0.0
    /// Whether some of the text isn't shown.
    var isTruncated = false
    /// Whether this is also the layout of every proposal between its own
    /// and `size`. It isn't when where the text is cut, how much it is
    /// tightened or how far it is scaled depends on the exact width.
    var holdsBetween = true
}

extension TextMeasurer {

    /// One layout a text was asked for, with the proposal it was made under.
    private struct LayoutEntry {
        let proposal: ProposedSize
        let layout: TextLayout

        /// Whether this layout is also the one `other` gets.
        ///
        /// On each axis the lines only change when the proposal leaves the
        /// range between the proposal and the size the lines took. Every
        /// line fitted the proposal, so it fits anything down to the widest
        /// of them. Every break was made because the next word overflowed
        /// the proposal, so it overflows anything narrower too. The same
        /// words then break the same way anywhere in between. The lines a
        /// height has room for, and a tail cut, follow the same rule.
        ///
        /// No width, or an infinite one, isn't broken at all. Its lines are
        /// whole paragraphs, each measured in one sum, where breaking adds a
        /// line up word by word and can come out a hair wider; a layout made
        /// with one answers only that same width, and none other answers it.
        func answers(_ other: ProposedSize) -> Bool {
            guard layout.holdsBetween else { return other == proposal }
            guard Self.breaks(proposal.width), Self.breaks(other.width) else {
                return other.width == proposal.width
                    && Self.isBetween(other.height, proposal.height, layout.size.height)
            }
            return Self.isBetween(other.width, proposal.width, layout.size.width)
                && Self.isBetween(other.height, proposal.height, layout.size.height)
        }

        private static func breaks(_ width: Double?) -> Bool {
            width.map { $0 < .infinity } ?? false
        }

        /// An unspecified axis is an unbounded one.
        private static func isBetween(_ value: Double?, _ proposed: Double?, _ answered: Double) -> Bool {
            let value = value ?? .infinity
            let proposed = proposed ?? .infinity
            return min(proposed, answered) <= value && value <= max(proposed, answered)
        }
    }

    /// The layouts each text was last asked for, oldest first.
    private static var layouts: [TextLayoutInput: [LayoutEntry]] = [:]

    /// The most layouts one text keeps: a text resized a long way keeps the
    /// latest.
    private static let layoutsPerText = 8

    /// `input` laid out under `proposal`.
    ///
    /// Text sizing is the leaf of every layout pass and by far its most
    /// expensive step, so layouts are kept across passes as well as within
    /// one: the same label measured again after a state change has not
    /// changed shape, and a stack that offers a text several widths, or a
    /// window being resized, mostly lands between widths already measured.
    static func layout(_ input: TextLayoutInput, proposal: ProposedSize) -> TextLayout {
        if let hit = layouts[input]?.first(where: { $0.answers(proposal) }) {
            return hit.layout
        }
        let made = makeLayout(input, proposal: proposal)
        // A miss only: a long-running app showing ever-new strings (a
        // clock, a counter) would otherwise keep every one it ever showed.
        if layouts.count >= 4096 { layouts.removeAll(keepingCapacity: true) }
        layouts[input, default: []].append(LayoutEntry(proposal: proposal, layout: made))
        if layouts[input]!.count > layoutsPerText { layouts[input]!.removeFirst() }
        return made
    }

    /// `input` laid out under `proposal` from scratch, without looking at
    /// or keeping any layout.
    static func makeLayout(_ input: TextLayoutInput, proposal: ProposedSize) -> TextLayout {
        let face = Self.face(for: input.font, spacing: input.letterSpacing)
        let lineHeight = lineMetrics(face: face).lineHeight
        guard !input.string.isEmpty else {
            return TextLayout(lines: [], size: Size(width: 0, height: lineHeight))
        }
        let paragraph = input.paragraph
        let offset = abs(input.baselineOffset)
        // The lower line limit's lines, line spacing left out, kept whatever
        // the proposal.
        let reserved = Double(max(paragraph.reservedLines, 0)) * lineHeight
        let maxHeight = proposal.height.map { max($0 - offset, reserved) }

        var layout = fit(input, face: face, maxWidth: proposal.width, maxHeight: maxHeight)
        // Negative spacing can make a longer line the narrower one, which
        // the range a layout answers for relies on never happening.
        if input.letterSpacing < 0 { layout.holdsBetween = false }
        let minimum = paragraph.minimumScaleFactor
        if layout.isTruncated, minimum > 0, minimum < 1 {
            layout = scaledToFit(input, minimum: minimum, maxWidth: proposal.width, maxHeight: maxHeight)
        }
        layout.size.height = max(layout.size.height, reserved) + offset
        return layout
    }

    /// The text set as large as it fits, but no smaller than `minimum` of
    /// its size; at `minimum` and cut when even that doesn't fit. Scales go
    /// in hundredths, so a text resized slowly is drawn at a handful of
    /// sizes rather than at a new one every frame.
    private static func scaledToFit(_ input: TextLayoutInput, minimum: Double, maxWidth: Double?, maxHeight: Double?) -> TextLayout {
        func attempt(_ hundredths: Int) -> TextLayout {
            let scale = Double(hundredths) / 100
            let face = Self.face(for: input.font.size(input.font.size * scale), spacing: input.letterSpacing)
            var layout = fit(input, face: face, maxWidth: maxWidth, maxHeight: maxHeight)
            layout.scale = scale
            layout.holdsBetween = false
            return layout
        }
        var low = min(100, max(1, Int((minimum * 100).rounded(.up))))
        var best = attempt(low)
        guard !best.isTruncated else { return best }
        // `low` fits, and 100 — the text's own size — doesn't.
        var high = 100
        while high - low > 1 {
            let middle = (low + high) / 2
            let tried = attempt(middle)
            if tried.isTruncated {
                high = middle
            } else {
                low = middle
                best = tried
            }
        }
        return best
    }

    /// The lines of `input` set in `face`: broken to `maxWidth`, as many as
    /// the line limit and `maxHeight` leave room for, the last one shown
    /// made from the rest of the text.
    private static func fit(_ input: TextLayoutInput, face: Int, maxWidth: Double?, maxHeight: Double?) -> TextLayout {
        let paragraph = input.paragraph
        let lineHeight = lineMetrics(face: face).lineHeight
        let lineSpacing = max(paragraph.lineSpacing, 0)
        let shown = min(
            paragraph.lineLimit.map { max($0, 1) } ?? .max,
            maxHeight.map { linesFitting($0, lineHeight: lineHeight, lineSpacing: lineSpacing) } ?? .max
        )

        // The lines up to one past the last shown: enough to tell whether
        // any are left out. No width, or an infinite one, breaks only at
        // line feeds. A width of 0 breaks as narrow as the text goes, which
        // is how a stack learns how far a text can shrink, as in SwiftUI.
        let paragraphs = Self.paragraphs(of: input.string)
        var lines: [(paragraph: Int, range: Range<String.Index>)] = []
        for (index, text) in paragraphs.enumerated() {
            guard lines.count <= shown else { break }
            if let maxWidth, maxWidth < .infinity {
                breakLines(text, face: face, maxWidth: max(maxWidth, 0)) { range in
                    if lines.count <= shown { lines.append((index, range)) }
                }
            } else {
                lines.append((index, text.startIndex..<text.endIndex))
            }
        }

        let isCut = lines.count > shown
        let lastShown = min(lines.count, shown) - 1
        var drawn: [String] = []
        drawn.reserveCapacity(lastShown + 1)
        var widest = 0.0
        for line in lines[..<lastShown] {
            let text = paragraphs[line.paragraph][line.range]
            drawn.append(String(text))
            widest = max(widest, Self.width(of: text, face: face))
        }

        var layout = TextLayout(lines: [], size: .zero)
        let last = lines[lastShown]
        let lastText = paragraphs[last.paragraph][last.range]
        let lastWidth = Self.width(of: lastText, face: face)
        let room = maxWidth.map { max($0, 0) } ?? .infinity
        // A text left as long as it is keeps a character too wide for its
        // line, as every line before it does; one held to a line count or a
        // height cuts it.
        if isCut || (shown != .max && lastWidth > room) {
            let start = last.range.lowerBound
            let rest: String
            let hasMore: Bool
            switch paragraph.truncationMode {
            case .tail:
                // The rest of this paragraph; what follows it can't be on
                // this line, so it only asks for the ellipsis.
                rest = String(paragraphs[last.paragraph][start...])
                hasMore = paragraphs[(last.paragraph + 1)...].contains { $0.contains { $0 != " " } }
            case .head, .middle:
                // Everything from here to the end, line feeds as spaces:
                // the head mode shows how the whole text ends.
                rest = ([String(paragraphs[last.paragraph][start...])]
                    + paragraphs[(last.paragraph + 1)...].filter { !$0.isEmpty }).joined(separator: " ")
                hasMore = false
            }
            let made = lastLine(
                rest,
                hasMore: hasMore,
                mode: paragraph.truncationMode,
                allowsTightening: paragraph.allowsTightening,
                face: face,
                maxWidth: room
            )
            drawn.append(made.line)
            widest = max(widest, made.width)
            layout.lastLineTightening = made.tightening
            layout.isTruncated = made.isTruncated
            layout.holdsBetween = made.holdsBetween
        } else {
            drawn.append(String(lastText))
            widest = max(widest, lastWidth)
        }

        let count = Double(drawn.count)
        layout.lines = drawn
        layout.size = Size(
            width: maxWidth.map { min(widest, max($0, 0)) } ?? widest,
            height: lineHeight * count + lineSpacing * (count - 1)
        )
        return layout
    }

    /// The lines `height` has room for, never fewer than one.
    private static func linesFitting(_ height: Double, lineHeight: Double, lineSpacing: Double) -> Int {
        let step = lineHeight + lineSpacing
        guard step > 0 else { return .max }
        // A hair over, so a height measured for n lines holds n of them.
        let count = ((height + lineSpacing) / step + 1e-9).rounded(.down)
        // Unbounded too: an infinite height, or one too tall to count.
        guard count < 1e9 else { return .max }
        return max(1, Int(count))
    }

    /// The last line shown, made from `rest`, the text from its start on.
    /// Whole when it fits `maxWidth`, or when tightening is allowed and
    /// enough; otherwise cut where `mode` says, with an ellipsis.
    /// `hasMore`: text after `rest` is left out as well, so the line ends in
    /// an ellipsis however much of `rest` it holds.
    ///
    /// Each cut is found in one walk, summing advances from the end that is
    /// kept, rather than by measuring every shorter candidate in full.
    private static func lastLine(
        _ rest: String,
        hasMore: Bool,
        mode: Text.TruncationMode,
        allowsTightening: Bool,
        face: Int,
        maxWidth: Double
    ) -> (line: String, width: Double, tightening: Double, isTruncated: Bool, holdsBetween: Bool) {
        let natural = Self.width(of: rest, face: face)
        if !hasMore, natural <= maxWidth {
            return (rest, natural, 0, false, true)
        }
        // Squeezed by at most 3 % of its width, spread over its characters.
        if !hasMore, allowsTightening, natural - maxWidth <= natural * 0.03 {
            return (rest, maxWidth, -(natural - maxWidth) / Double(rest.count), false, false)
        }

        let ellipsis = advance("…", face: face)
        switch mode {
        case .tail:
            // Summed in the order the kept line is measured in, so the line
            // is the same for any width down to its own.
            var sum = 0.0
            var end = rest.startIndex
            while end < rest.endIndex {
                let next = sum + advance(rest[end], face: face)
                if next + ellipsis > maxWidth { break }
                sum = next
                rest.formIndex(after: &end)
            }
            var kept = rest[..<end]
            while kept.last == " " { kept.removeLast() }
            let line = String(kept) + "…"
            return (line, Self.width(of: line, face: face), 0, true, true)

        case .head:
            var sum = 0.0
            var start = rest.endIndex
            while start > rest.startIndex {
                let before = rest.index(before: start)
                let next = sum + advance(rest[before], face: face)
                if next + ellipsis > maxWidth { break }
                sum = next
                start = before
            }
            var kept = rest[start...]
            while kept.first == " " { kept.removeFirst() }
            let line = "…" + kept
            return (line, Self.width(of: line, face: face), 0, true, false)

        case .middle:
            // The start takes up to half the room, the end what is left.
            let room = maxWidth - ellipsis
            var startSum = 0.0
            var end = rest.startIndex
            while end < rest.endIndex {
                let next = startSum + advance(rest[end], face: face)
                if next > room / 2 { break }
                startSum = next
                rest.formIndex(after: &end)
            }
            var endSum = 0.0
            var start = rest.endIndex
            while start > end {
                let before = rest.index(before: start)
                let next = endSum + advance(rest[before], face: face)
                if startSum + next > room { break }
                endSum = next
                start = before
            }
            var head = rest[..<end]
            while head.last == " " { head.removeLast() }
            var tail = rest[start...]
            while tail.first == " " { tail.removeFirst() }
            let line = String(head) + "…" + tail
            return (line, Self.width(of: line, face: face), 0, true, false)
        }
    }

    // MARK: - Underline and strikethrough

    /// Where the lines under and through a text in `font` go, as the
    /// distance of each line's center below the baseline (above it when
    /// negative), and how thick they are. In proportion to the face's own
    /// metrics, so both renderers draw them in the same place.
    static func decorationMetrics(for font: Font) -> (underline: Double, strikethrough: Double, thickness: Double) {
        let metrics = lineMetrics(for: font)
        let thickness = max(1, metrics.ascent / 16)
        return (metrics.descent * 0.35 + thickness / 2, -metrics.ascent * 0.3, thickness)
    }

    /// The stretches of a line `length` long that `pattern` draws, from its
    /// start: one for a solid line, a dash or dot each otherwise.
    static func decorationDashes(length: Double, thickness: Double, pattern: Text.LineStyle.Pattern) -> [(start: Double, end: Double)] {
        guard length > 0 else { return [] }
        let intervals = pattern.intervals
        guard !intervals.isEmpty, thickness > 0 else { return [(0, length)] }
        var dashes: [(start: Double, end: Double)] = []
        var position = 0.0
        var index = 0
        while position < length {
            let on = intervals[index] * thickness
            dashes.append((position, min(position + on, length)))
            position += on + intervals[index + 1] * thickness
            index = (index + 2) % intervals.count
        }
        return dashes
    }
}
