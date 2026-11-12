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
    ]

    static let widths: [Double?] = [nil, 0, 1, 24, 60, 97.5, 140, 220, 1000, .infinity]
    static let lineLimits: [Int?] = [nil, 0, 1, 2, 3]
    static let fonts: [Font] = [.system(size: 13), .system(size: 22), .system(size: 15).italic()]

    /// The word-at-a-time algorithm, as it was before lines became ranges.
    static func referenceWrap(_ string: String, font: Font, maxWidth: Double?, lineLimit: Int?) -> [String] {
        let paragraphs = string.components(separatedBy: "\n")
        func limited(_ lines: [String]) -> [String] {
            guard let lineLimit, lineLimit > 0, lines.count > lineLimit else { return lines }
            return Array(lines.prefix(lineLimit))
        }
        guard let maxWidth, maxWidth > 0 else { return limited(paragraphs) }

        var lines: [String] = []
        for paragraph in paragraphs {
            var current = ""
            var currentWidth = 0.0
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let piece = current.isEmpty ? String(word) : " " + word
                let pieceWidth = TextMeasurer.width(of: piece, font: font)
                if !current.isEmpty && currentWidth + pieceWidth > maxWidth {
                    lines.append(current)
                    current = String(word)
                    currentWidth = TextMeasurer.width(of: String(word), font: font)
                } else {
                    current += piece
                    currentWidth += pieceWidth
                }
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
    /// it is a single word that can't be broken.
    @Test
    func wrappedLinesFitUnlessOneWord() {
        let font = Font.system(size: 14)
        let string = Self.strings[1]
        for width in [40.0, 80, 120, 200] {
            for line in TextMeasurer.wrap(string, font: font, maxWidth: width, lineLimit: nil) {
                let fits = TextMeasurer.width(of: line, font: font) <= width
                #expect(fits || !line.contains(" "), "\(line.debugDescription) at \(width)")
            }
        }
    }
}
