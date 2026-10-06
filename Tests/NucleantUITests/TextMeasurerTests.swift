//
//  TextMeasurerTests.swift
//  NucleantUITests
//
//  Line breaking and text sizing: `wrap` and `size(of:)` give exactly the
//  lines and boxes of the straightforward word-at-a-time algorithm — a
//  string built per word, its advances summed from zero — on the strings
//  that trip a line breaker up: runs of spaces, leading and trailing
//  spaces, empty paragraphs, a word wider than the line, line limits.
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

    static func referenceSize(_ string: String, font: Font, proposal: ProposedSize, lineLimit: Int?) -> Size {
        let lineHeight = TextMeasurer.lineMetrics(for: font).lineHeight
        guard !string.isEmpty else { return Size(width: 0, height: lineHeight) }
        let lines = referenceWrap(string, font: font, maxWidth: proposal.width, lineLimit: lineLimit)
        let widest = lines.reduce(0.0) { max($0, TextMeasurer.width(of: $1, font: font)) }
        return Size(
            width: proposal.width.map { min(widest, $0) } ?? widest,
            height: lineHeight * Double(lines.count)
        )
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

    @Test
    func sizeMatchesTheLinesWrapGives() {
        for font in Self.fonts {
            for string in Self.strings + [""] {
                for width in Self.widths {
                    for lineLimit in Self.lineLimits {
                        let proposal = ProposedSize(width: width, height: nil)
                        let size = TextMeasurer.size(of: string, font: font, proposal: proposal, lineLimit: lineLimit)
                        let expected = Self.referenceSize(string, font: font, proposal: proposal, lineLimit: lineLimit)
                        #expect(size == expected, "\(string.debugDescription) at \(String(describing: width)), limit \(String(describing: lineLimit))")
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
