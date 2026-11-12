//
//  TextMeasurerTests.swift
//  NucleantUITests
//
//  Line breaking and text sizing: `wrap` and `layout` give exactly the
//  lines and boxes of the straightforward word-at-a-time algorithm — a
//  string built per word, its advances summed from zero — on the strings
//  that trip a line breaker up: runs of spaces, leading and trailing
//  spaces, empty paragraphs, a word wider than the line, line limits. A
//  layout's last line, where lines are left out, is the one exception: the
//  rest of the text, cut to fit.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct TextMeasurerTests {

    static let strings = [
        "Local-first software",
        "Why the apps we build should keep working offline, keep the user's data on the user's device, and still collaborate in real time.",
        "  leading spaces and trailing ones  ",
        "double  spaces   and    more",
        "first paragraph\nsecond paragraph, a little longer\n\nafter an empty one",
        "Supercalifragilisticexpialidocious is wider than any line here",
        "café, naïve, 東京, emoji 👩‍👩‍👧 and e\u{301} combining",
        "a b c d e f g h i j k l m n o p q r s t u v w x y z",
        " ",
        "\n",
        "x",
        "windows\r\nline ends\r\nand a lone\rcarriage return",
        "ascii then combining: cafe\u{301} and n\u{303}o, then more ascii",
        "\u{301}starts with a combining mark",
        "nucleantshowcase://category/sensors",
        "a well-known path/to/some/file — one–two—three, v1/2024/v2-3 and -flag",
        "    indented, with a-very-long-hyphenated-identifier-that-wraps",
    ]

    static let widths: [Double?] = [nil, 0, 1, 24, 60, 97.5, 140, 220, 1000, .infinity]
    static let lineLimits: [Int?] = [nil, 0, 1, 2, 3]
    static let fonts: [Font] = [.system(size: 13), .system(size: 22), .system(size: 15).italic()]

    /// The word-at-a-time algorithm: a string built per word, words joined
    /// by single spaces, each line measured whole. A paragraph's indent is
    /// kept, on a line of its own when the first word doesn't fit after it;
    /// a line begun by a break drops the spaces before it.
    ///
    /// A word that doesn't fit after a space ends the line after as many of
    /// its pieces — up to each place it may break — as fit, or before it.
    /// What then starts a line and is too wide for it is added a character
    /// at a time, a line ended at the last place it may break before the
    /// character that overflows it, or right before that character.
    static func referenceWrap(_ string: String, font: Font, maxWidth: Double?, lineLimit: Int?) -> [String] {
        let paragraphs = string.components(separatedBy: "\n")
        func limited(_ lines: [String]) -> [String] {
            guard let lineLimit, lineLimit > 0, lines.count > lineLimit else { return lines }
            return Array(lines.prefix(lineLimit))
        }
        guard let maxWidth, maxWidth > 0 else { return limited(paragraphs) }
        func width(_ string: String) -> Double { TextMeasurer.width(of: string, font: font) }

        var lines: [String] = []
        var current = ""
        var currentWidth = 0.0

        /// How many of the word's characters come before each place it
        /// may break.
        func places(in characters: [Character]) -> [Int] {
            (0..<max(0, characters.count - 1)).filter { index in
                index > 0 && TextMeasurer.breaksAfter(characters[index], before: characters[index + 1])
            }.map { $0 + 1 }
        }

        /// The word's characters from `offset` on, starting a line.
        func start(_ characters: [Character], from offset: Int, places: [Int]) {
            let rest = String(characters[offset...])
            if width(rest) <= maxWidth {
                current = rest
                currentWidth = width(rest)
                return
            }
            current = ""
            var cut: Int?
            for index in offset..<characters.count {
                let character = String(characters[index])
                if !current.isEmpty && width(current + character) > maxWidth, let at = cut {
                    lines.append(String(current.prefix(at)))
                    current = String(current.dropFirst(at))
                    cut = nil
                }
                if !current.isEmpty && width(current + character) > maxWidth {
                    lines.append(current)
                    current = ""
                }
                current += character
                if places.contains(index + 1) { cut = current.count }
            }
            currentWidth = width(current)
        }

        /// The word after a space on a line that has something on it.
        func append(_ word: Substring) {
            let piece = " " + word
            if currentWidth + width(piece) <= maxWidth {
                current += piece
                currentWidth += width(piece)
                return
            }
            let characters = Array(word)
            let places = places(in: characters)
            var fitting: Int?
            for place in places {
                guard currentWidth + width(" " + String(characters[..<place])) <= maxWidth else { break }
                fitting = place
            }
            if let fitting {
                lines.append(current + " " + String(characters[..<fitting]))
                start(characters, from: fitting, places: places)
            } else {
                lines.append(current)
                start(characters, from: 0, places: places)
            }
        }

        for paragraph in paragraphs {
            current = ""
            currentWidth = 0.0
            var inIndent = true
            for (index, word) in paragraph.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
                if inIndent {
                    if index == 0 {
                        guard !word.isEmpty else { continue }
                        inIndent = false
                        start(Array(word), from: 0, places: places(in: Array(word)))
                        continue
                    }
                    if word.isEmpty {
                        current += " "
                        currentWidth += width(" ")
                        continue
                    }
                    inIndent = false
                } else if current.isEmpty {
                    start(Array(word), from: 0, places: places(in: Array(word)))
                    continue
                }
                append(word)
            }
            lines.append(current)
        }
        return limited(lines)
    }


    @Test
    func wrapBreaksWhereTheWordAtATimeAlgorithmDoes() {
        for font in Self.fonts {
            for string in Self.strings {
                for width in Self.widths {
                    for lineLimit in Self.lineLimits {
                        let lines = TextMeasurer.wrap(string, font: font, maxWidth: width, lineLimit: lineLimit)
                        let expected = Self.referenceWrap(string, font: font, maxWidth: width, lineLimit: lineLimit)
                        #expect(lines == expected, "\(string.debugDescription) at \(String(describing: width)), limit \(String(describing: lineLimit))")
                    }
                }
            }
        }
    }

    /// The lines a layout shows are the word-at-a-time algorithm's, as many
    /// as the limit allows (a limit of 0 is one line). Only the last one
    /// shown differs, and only when lines are left out or it is too wide:
    /// it is the rest of the text, cut at its tail with an ellipsis to fit,
    /// or whole when it fits and nothing after it is left out.
    @Test
    func layoutKeepsTheWrappedLinesAndCutsOnlyTheLast() {
        for font in Self.fonts {
            let lineHeight = TextMeasurer.lineMetrics(for: font).lineHeight
            for string in Self.strings {
                for width in Self.widths {
                    for lineLimit in Self.lineLimits {
                        let context: Comment = "\(string.debugDescription) at \(String(describing: width)), limit \(String(describing: lineLimit))"
                        let input = TextLayoutInput(string: string, font: font, paragraph: TextParagraphStyle(lineLimit: lineLimit))
                        let layout = TextMeasurer.layout(input, proposal: ProposedSize(width: width, height: nil))
                        let all = Self.referenceWrap(string, font: font, maxWidth: width, lineLimit: nil)
                        let room = width.flatMap { $0 > 0 ? $0 : nil } ?? .infinity
                        #expect(layout.size.height == lineHeight * Double(layout.lines.count), context)

                        let limit = lineLimit.map { max($0, 1) }
                        let shown = min(limit ?? .max, all.count)
                        let isCut = all.count > shown
                            || (limit != nil && TextMeasurer.width(of: all[shown - 1], font: font) > room)
                        guard isCut else {
                            #expect(layout.lines == all, context)
                            #expect(!layout.isTruncated, context)
                            let widest = all.reduce(0.0) { max($0, TextMeasurer.width(of: $1, font: font)) }
                            #expect(layout.size.width == (width.map { min(widest, $0) } ?? widest), context)
                            continue
                        }

                        #expect(layout.lines.count == shown, context)
                        #expect(Array(layout.lines.prefix(shown - 1)) == Array(all.prefix(shown - 1)), context)
                        guard let last = layout.lines.last else { continue }
                        let wrapped = all[shown - 1]
                        if last.hasSuffix("…") {
                            let kept = String(last.dropLast())
                            #expect(layout.isTruncated, context)
                            #expect(kept.hasPrefix(wrapped) || wrapped.hasPrefix(kept), context)
                            #expect(kept.isEmpty || TextMeasurer.width(of: last, font: font) <= room, context)
                        } else {
                            #expect(!layout.isTruncated, context)
                            #expect(last.hasPrefix(wrapped), context)
                        }
                    }
                }
            }
        }
    }

    @Test
    func anEmptyStringIsOneEmptyLine() {
        for font in Self.fonts {
            let layout = TextMeasurer.layout(TextLayoutInput(string: "", font: font), proposal: ProposedSize(width: 100, height: nil))
            #expect(layout.lines.isEmpty)
            #expect(layout.size == Size(width: 0, height: TextMeasurer.lineMetrics(for: font).lineHeight))
        }
    }

    /// A kept layout answers a proposal between its own and its size, and
    /// it is then exactly what making one from scratch there gives — for
    /// widths and heights asked for in any order, every truncation mode,
    /// tightening and scaling.
    @Test
    func keptLayoutsAnswerWhatMakingOneWould() {
        let widths: [Double?] = [nil, 400, 320, 250, 251, 180, 179.5, 140, 141, 97.5, 60, 61, 24, 0, 1000, .infinity, 150, 150.25]
        let heights: [Double?] = [nil, 10, 40, 41, 80, 200, .infinity]
        let paragraphs: [TextParagraphStyle] = [
            TextParagraphStyle(),
            TextParagraphStyle(lineLimit: 1),
            TextParagraphStyle(lineLimit: 2, truncationMode: .head),
            TextParagraphStyle(lineLimit: 1, truncationMode: .middle),
            TextParagraphStyle(lineLimit: 3, reservedLines: 2, lineSpacing: 6),
            TextParagraphStyle(lineLimit: 1, allowsTightening: true),
            TextParagraphStyle(lineLimit: 1, minimumScaleFactor: 0.5),
        ]
        for font in [Font.system(size: 13), .system(size: 22)] {
            for string in Self.strings {
                for paragraph in paragraphs {
                    for spacing in [0.0, 1.5] {
                        let input = TextLayoutInput(string: string, font: font, letterSpacing: spacing, baselineOffset: 3, paragraph: paragraph)
                        for height in heights {
                            for width in widths {
                                let proposal = ProposedSize(width: width, height: height)
                                #expect(
                                    TextMeasurer.layout(input, proposal: proposal) == TextMeasurer.makeLayout(input, proposal: proposal),
                                    "\(string.debugDescription) \(paragraph) at \(proposal)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /// A string's width is the sum of its characters' advances, added left
    /// to right — however it is walked to get them.
    @Test
    func widthIsTheSumOfItsCharacters() {
        for font in Self.fonts {
            for string in Self.strings + ["", "\r\n", "\r", "e\u{301}", "ab\r\ncd", "abc👩‍👩‍👧def"] {
                let expected = string.reduce(0.0) { $0 + TextMeasurer.width(of: String($1), font: font) }
                #expect(TextMeasurer.width(of: string, font: font) == expected, "\(string.debugDescription)")
            }
        }
    }

    /// A wrapped line is never wider than the line it was wrapped to, unless
    /// it is one character, after the paragraph's indent, too wide on its
    /// own — or a paragraph of nothing but spaces.
    @Test
    func wrappedLinesFitUnlessOneCharacter() {
        let font = Font.system(size: 14)
        for string in Self.strings {
            for width in [4.0, 12, 24, 40, 80, 120, 200] {
                for line in TextMeasurer.wrap(string, font: font, maxWidth: width, lineLimit: nil) {
                    let fits = TextMeasurer.width(of: line, font: font) <= width
                    #expect(fits || line.drop(while: { $0 == " " }).count <= 1, "\(line.debugDescription) at \(width)")
                }
            }
        }
    }
}
