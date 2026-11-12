//
//  TextLayoutTests.swift
//  NucleantUITests
//
//  A text laid out under one proposal: line limits (0 and below are one
//  line), the room a lower limit keeps, the lines a height lets through,
//  where each truncation mode cuts the last line, tightening and scaling
//  down to fit, line spacing, the baseline offset, letter spacing.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct TextLayoutTests {

    static let font = Font.system(size: 13)
    static let sentence = "The quick brown fox jumps over the lazy dog again and again"
    static var lineHeight: Double { TextMeasurer.lineMetrics(for: font).lineHeight }

    private func layout(
        _ string: String = sentence,
        width: Double? = 150,
        height: Double? = nil,
        letterSpacing: Double = 0,
        baselineOffset: Double = 0,
        paragraph: TextParagraphStyle = TextParagraphStyle()
    ) -> TextLayout {
        TextMeasurer.layout(
            TextLayoutInput(string: string, font: Self.font, letterSpacing: letterSpacing, baselineOffset: baselineOffset, paragraph: paragraph),
            proposal: ProposedSize(width: width, height: height)
        )
    }

    private func width(_ string: String) -> Double {
        TextMeasurer.width(of: string, font: Self.font)
    }

    // MARK: - Line limits

    @Test func aLimitOfZeroOrBelowIsOneLine() {
        for limit in [0, -2, 1] {
            let laid = layout(paragraph: TextParagraphStyle(lineLimit: limit))
            #expect(laid.lines.count == 1, "limit \(limit)")
            #expect(laid.size.height == Self.lineHeight, "limit \(limit)")
            #expect(laid.isTruncated, "limit \(limit)")
        }
    }

    @Test func aLowerLimitKeepsRoomForItsLines() {
        let three = layout("A", paragraph: TextParagraphStyle(lineLimit: 3, reservedLines: 3))
        #expect(three.lines == ["A"])
        #expect(three.size.height == 3 * Self.lineHeight)
        // Line spacing isn't in the room kept.
        let spaced = layout("A", paragraph: TextParagraphStyle(lineLimit: 3, reservedLines: 3, lineSpacing: 10))
        #expect(spaced.size.height == 3 * Self.lineHeight)
        // Kept whatever the proposal.
        let squeezed = layout("A", height: 5, paragraph: TextParagraphStyle(reservedLines: 3))
        #expect(squeezed.size.height == 3 * Self.lineHeight)
        // An empty text keeps none.
        #expect(layout("", paragraph: TextParagraphStyle(reservedLines: 3)).size.height == Self.lineHeight)
    }

    @Test func aHeightLimitsTheLines() {
        let all = layout()
        #expect(all.lines.count >= 3)
        for (height, lines) in [(5.0, 1), (Self.lineHeight - 1, 1), (2 * Self.lineHeight, 2), (2 * Self.lineHeight + 1, 2), (1000, all.lines.count)] {
            let laid = layout(height: height)
            #expect(laid.lines.count == lines, "height \(height)")
            #expect(laid.isTruncated == (lines < all.lines.count), "height \(height)")
            if lines < all.lines.count {
                #expect(laid.lines.last?.hasSuffix("…") == true, "height \(height)")
            }
        }
    }

    @Test func aHeightLeavesRoomForTheLineSpacing() {
        let paragraph = TextParagraphStyle(lineSpacing: 6)
        #expect(layout(height: 2 * Self.lineHeight + 6, paragraph: paragraph).lines.count == 2)
        #expect(layout(height: 2 * Self.lineHeight + 5, paragraph: paragraph).lines.count == 1)
    }

    // MARK: - Truncation

    @Test func tailKeepsTheStart() {
        let laid = layout(paragraph: TextParagraphStyle(lineLimit: 1))
        let line = laid.lines[0]
        #expect(line.hasPrefix("The quick"))
        #expect(line.hasSuffix("…"))
        #expect(!line.dropLast().hasSuffix(" "))
        #expect(width(line) <= 150)
        // The longest start that fits: up to the next character that isn't
        // a space doesn't.
        let characters = Array(Self.sentence)
        var next = line.count - 1
        while characters[next] == " " { next += 1 }
        #expect(width(String(characters[...next]) + "…") > 150)
    }

    @Test func headKeepsTheEnd() {
        let line = layout(paragraph: TextParagraphStyle(lineLimit: 1, truncationMode: .head)).lines[0]
        #expect(line.hasPrefix("…"))
        #expect(line.hasSuffix("again and again"))
        #expect(!line.dropFirst().hasPrefix(" "))
        #expect(width(line) <= 150)
    }

    @Test func middleKeepsBothEnds() {
        let line = layout(paragraph: TextParagraphStyle(lineLimit: 1, truncationMode: .middle)).lines[0]
        #expect(line.hasPrefix("The"))
        #expect(line.hasSuffix("again"))
        #expect(line.contains("…") && !line.hasPrefix("…") && !line.hasSuffix("…"))
        #expect(width(line) <= 150)
        let halves = line.split(separator: "…", omittingEmptySubsequences: false)
        #expect(halves.count == 2)
        // Each end takes about half the room.
        #expect(abs(width(String(halves[0])) - width(String(halves[1]))) < 20)
    }

    @Test func severalLinesWrapAndOnlyTheLastIsCut() {
        let wrapped = TextMeasurer.wrap(Self.sentence, font: Self.font, maxWidth: 150, lineLimit: nil)
        for mode in [Text.TruncationMode.tail, .head, .middle] {
            let laid = layout(paragraph: TextParagraphStyle(lineLimit: 2, truncationMode: mode))
            #expect(laid.lines.count == 2)
            #expect(laid.lines[0] == wrapped[0], "\(mode)")
            #expect(laid.lines[1].contains("…"), "\(mode)")
            #expect(width(laid.lines[1]) <= 150, "\(mode)")
        }
        // Head shows how the whole text ends, after the first line.
        #expect(layout(paragraph: TextParagraphStyle(lineLimit: 2, truncationMode: .head)).lines[1].hasSuffix("again and again"))
    }

    @Test func aCutParagraphBeforeAnotherEndsInAnEllipsis() {
        let laid = layout("Short\nand another paragraph", width: 300, paragraph: TextParagraphStyle(lineLimit: 1))
        #expect(laid.lines == ["Short…"])
        #expect(laid.isTruncated)
        // A trailing line feed leaves nothing out.
        #expect(layout("Short\n", width: 300, paragraph: TextParagraphStyle(lineLimit: 1)).lines == ["Short"])
    }

    @Test func aWordTooLongBreaksBetweenCharacters() {
        let word = "Supercalifragilisticexpialidocious"
        let lines = layout(word, width: 60).lines
        #expect(lines.count > 1)
        #expect(lines.joined() == word)
        #expect(lines.allSatisfy { width($0) <= 60 })
        // Each line but the last is as full as it can be.
        for (line, next) in zip(lines, lines.dropFirst()) {
            #expect(width(line + String(next.first!)) > 60, "\(line)")
        }
        // Limited to one line, it is cut instead.
        let limited = layout(word, width: 60, paragraph: TextParagraphStyle(lineLimit: 1)).lines
        #expect(limited.count == 1)
        #expect(limited[0].hasSuffix("…") && width(limited[0]) <= 60)
    }

    @Test func aWordTooLongStartsItsOwnLine() {
        // It isn't begun on the end of a line that already has a word.
        let lines = layout("a Supercalifragilisticexpialidocious b", width: 60).lines
        #expect(lines.first == "a")
        #expect(lines.dropFirst().joined().hasPrefix("Supercalifragilisticexpialidocious"))
        // Its last piece goes on with the words after it.
        #expect(lines.last?.hasSuffix(" b") == true)
    }

    @Test func aBrokenWordIsCutOnItsLastLineShown() {
        let word = "Supercalifragilisticexpialidocious"
        let lines = layout(word, width: 60, paragraph: TextParagraphStyle(lineLimit: 2)).lines
        #expect(lines.count == 2)
        #expect(lines[1].hasSuffix("…"))
        #expect(word.hasPrefix(lines[0] + String(lines[1].dropLast())))
    }

    @Test func aCharacterWiderThanTheLineStillGetsOne() {
        #expect(layout("WWW", width: 2).lines == ["W", "W", "W"])
    }

    @Test func aWordBreaksAfterAHyphenOrASlash() {
        // Each line holds as many pieces as fit.
        let hyphenated = "well-known-identifier-name"
        let lines = layout(hyphenated, width: width("well-known-") + 1).lines
        #expect(lines.first == "well-known-")
        #expect(lines.joined() == hyphenated)
        let path = "path/to/some/file/name"
        #expect(layout(path, width: width("path/to/") + 1).lines.first == "path/to/")
        #expect(layout("one–two—three", width: width("one–two—") + 1).lines.first == "one–two—")
    }

    @Test func aWordAfterOthersBreaksAtItsHyphen() {
        // Rather than move to the next line whole.
        let lines = layout("the well-known name", width: width("the well-") + 1).lines
        #expect(lines == ["the well-", "known", "name"])
    }

    @Test func theURLBreaksAfterItsSlashes() {
        let url = "nucleantshowcase://category/sensors"
        let lines = layout(url, width: width("nucleantshowcase://category") - 1).lines
        #expect(lines == ["nucleantshowcase://", "category/sensors"])
    }

    @Test func placesAWordMayBreak() {
        #expect(TextMeasurer.breaksAfter("-", before: "k"))
        #expect(TextMeasurer.breaksAfter("/", before: "c"))
        #expect(TextMeasurer.breaksAfter("\u{2013}", before: "t"))
        #expect(TextMeasurer.breaksAfter("\u{2014}", before: "t"))
        // Not before a digit, more of the same, or closing punctuation.
        #expect(!TextMeasurer.breaksAfter("-", before: "3"))
        #expect(!TextMeasurer.breaksAfter("/", before: "2"))
        #expect(!TextMeasurer.breaksAfter("/", before: "/"))
        #expect(!TextMeasurer.breaksAfter("-", before: "-"))
        #expect(!TextMeasurer.breaksAfter("-", before: ")"))
        #expect(!TextMeasurer.breaksAfter("/", before: "."))
        // Nor after anything else.
        for character: Character in ["_", ".", ":", "?", "&", "=", "a", "東"] {
            #expect(!TextMeasurer.breaksAfter(character, before: "x"), "\(character)")
        }
    }

    @Test func noBreakAfterAWordsFirstCharacterOrBeforeADigit() {
        // "-flag" keeps its hyphen; "v1/2024" its slash.
        let flag = layout("-flagname", width: width("-f") + 0.5).lines
        #expect(flag.first == "-f")
        let version = layout("v1/2024", width: width("v1/2") + 0.5).lines
        #expect(version.first == "v1/2")
    }

    @Test func aWidthOfZeroIsAsNarrowAsTheTextGoes() {
        // As SwiftUI's: how a stack learns how far a text can shrink.
        let laid = layout("Hi there", width: 0)
        #expect(laid.lines == ["H", "i", "t", "h", "e", "r", "e"])
        #expect(laid.size.width == 0)
        #expect(laid.size.height == 7 * Self.lineHeight)
        // No width, or an infinite one, is still a line a paragraph.
        #expect(layout("Hi there", width: nil).lines == ["Hi there"])
        #expect(layout("Hi there", width: .infinity).lines == ["Hi there"])
    }

    @Test func aWideWordIsKeptWholeWithoutAWidth() {
        let word = "Supercalifragilisticexpialidocious"
        #expect(layout(word, width: nil).lines == [word])
    }

    // MARK: - Indents

    /// Indented lines, one long enough to wrap at 200 points and none at 560.
    static let json = "{\n    \"name\": \"a value long enough to wrap\",\n    \"id\": 7\n}"

    private func jsonLines(width: Double) -> [String] {
        TextMeasurer.layout(
            TextLayoutInput(string: Self.json, font: .system(size: 15, design: .monospaced)),
            proposal: ProposedSize(width: width, height: nil)
        ).lines
    }

    @Test func eachParagraphKeepsItsIndent() {
        for width in [200.0, 560] {
            let lines = jsonLines(width: width)
            #expect(lines.first == "{", "\(width)")
            #expect(lines.contains { $0.hasPrefix("    \"name\": ") }, "\(width)")
            #expect(lines.dropLast().last == "    \"id\": 7", "\(width)")
            #expect(lines.last == "}", "\(width)")
        }
        // Where nothing wraps, the lines are the paragraphs, as with no width.
        #expect(jsonLines(width: 560) == Self.json.components(separatedBy: "\n"))
    }

    @Test func aLineBegunByABreakStartsAtItsWord() {
        let lines = jsonLines(width: 200)
        #expect(lines.count > 4)
        // Between the name's first line and the id's: where the name wrapped.
        let wrapped = lines[2..<(lines.count - 2)]
        #expect(!wrapped.isEmpty)
        #expect(wrapped.allSatisfy { !$0.hasPrefix(" ") })
    }

    @Test func anIndentTooWideForItsWordIsALineOfItsOwn() {
        // As in SwiftUI: the line breaks after the indent, and the word
        // starts the next one, broken only if it doesn't fit there either.
        let lines = layout("        word and more", width: 40).lines
        #expect(lines.first?.allSatisfy { $0 == " " } == true)
        #expect(lines.dropFirst().first == "word")
        #expect(String(lines.joined().filter { $0 != " " }) == "wordandmore")
        let narrow = layout("        word", width: 1).lines
        #expect(narrow.first?.allSatisfy { $0 == " " } == true)
        #expect(Array(narrow.dropFirst()) == ["w", "o", "r", "d"])
        // A paragraph of spaces is kept as it is.
        #expect(layout("   ", width: 100).lines == ["   "])
        #expect(layout("a\n   \nb", width: 100).lines == ["a", "   ", "b"])
    }

    @Test func anEllipsisAloneWhenNothingElseFits() {
        #expect(layout(width: 4, paragraph: TextParagraphStyle(lineLimit: 1)).lines == ["…"])
    }

    // MARK: - Tightening and scaling

    @Test func tighteningFitsALineSlightlyTooWide() {
        let natural = width(Self.sentence)
        let narrow = natural * 0.985
        let tight = layout(width: narrow, paragraph: TextParagraphStyle(lineLimit: 1, allowsTightening: true))
        #expect(tight.lines == [Self.sentence])
        #expect(!tight.isTruncated)
        #expect(tight.lastLineTightening < 0)
        #expect(abs(tight.lastLineTightening * Double(Self.sentence.count) + (natural - narrow)) < 1e-9)
        #expect(tight.size.width == narrow)

        let loose = layout(width: narrow, paragraph: TextParagraphStyle(lineLimit: 1))
        #expect(loose.lines[0].hasSuffix("…"))
        #expect(loose.lastLineTightening == 0)

        // Too far over to tighten.
        let far = layout(width: natural * 0.95, paragraph: TextParagraphStyle(lineLimit: 1, allowsTightening: true))
        #expect(far.lines[0].hasSuffix("…"))
        #expect(far.lastLineTightening == 0)
    }

    @Test func aMinimumScaleShrinksTheTextToFit() {
        let natural = width(Self.sentence)
        let laid = layout(width: natural / 2, paragraph: TextParagraphStyle(lineLimit: 1, minimumScaleFactor: 0.3))
        #expect(laid.lines == [Self.sentence])
        #expect(!laid.isTruncated)
        #expect(laid.scale < 0.55 && laid.scale >= 0.3)
        #expect(laid.size.width <= natural / 2)
        // A scaled text answers a smaller height.
        #expect(laid.size.height < Self.lineHeight)
        // The largest scale that fits, in hundredths.
        let larger = Double(Int((laid.scale * 100).rounded()) + 1) / 100
        let face = TextMeasurer.face(for: Self.font.size(Self.font.size * larger))
        #expect(TextMeasurer.width(of: Self.sentence, face: face) > natural / 2)
    }

    @Test func aMinimumThatDoesntFitIsDrawnAtTheMinimumAndCut() {
        let natural = width(Self.sentence)
        let laid = layout(width: natural / 2, paragraph: TextParagraphStyle(lineLimit: 1, minimumScaleFactor: 0.8))
        #expect(laid.scale == 0.8)
        #expect(laid.isTruncated)
        #expect(laid.lines[0].hasSuffix("…"))
    }

    @Test func aTextThatFitsIsNotScaled() {
        let laid = layout(width: 1000, paragraph: TextParagraphStyle(lineLimit: 1, minimumScaleFactor: 0.5))
        #expect(laid.scale == 1)
        #expect(laid.lines == [Self.sentence])
    }

    @Test func severalLinesShrinkToFitTheirHeight() {
        let laid = layout(height: 2 * Self.lineHeight, paragraph: TextParagraphStyle(minimumScaleFactor: 0.4))
        #expect(!laid.isTruncated)
        #expect(laid.scale < 1)
        #expect(laid.size.height <= 2 * Self.lineHeight)
        #expect(laid.lines.joined(separator: " ") == Self.sentence)
    }

    // MARK: - Spacing and offset

    @Test func lineSpacingGoesBetweenLines() {
        let plain = layout()
        let spaced = layout(paragraph: TextParagraphStyle(lineSpacing: 10))
        #expect(spaced.lines == plain.lines)
        let count = Double(plain.lines.count)
        #expect(spaced.size.height == count * Self.lineHeight + (count - 1) * 10)
        // Negative spacing is none.
        #expect(layout(paragraph: TextParagraphStyle(lineSpacing: -5)).size.height == plain.size.height)
    }

    @Test func theBaselineOffsetGrowsTheBox() {
        for offset in [10.0, -10] {
            #expect(layout("Hello", baselineOffset: offset).size.height == Self.lineHeight + 10)
        }
    }

    @Test func letterSpacingIsAddedAfterEveryCharacter() {
        let plain = layout("Hello", width: nil)
        let spaced = layout("Hello", width: nil, letterSpacing: 3)
        #expect(abs(spaced.size.width - (plain.size.width + 5 * 3)) < 1e-9)
        let tighter = layout("Hello", width: nil, letterSpacing: -1)
        #expect(abs(tighter.size.width - (plain.size.width - 5)) < 1e-9)
    }

    @Test func letterSpacingBreaksLinesSooner() {
        let plain = layout()
        let spaced = layout(letterSpacing: 2)
        #expect(spaced.lines.count > plain.lines.count)
        for line in spaced.lines where line.contains(" ") {
            #expect(width(line) + 2 * Double(line.count) <= 150)
        }
    }

    // MARK: - Underline and strikethrough geometry

    @Test func decorationsSitUnderAndThroughTheText() {
        let metrics = TextMeasurer.lineMetrics(for: Self.font)
        let lines = TextMeasurer.decorationMetrics(for: Self.font)
        #expect(lines.thickness >= 1)
        #expect(lines.underline > 0 && lines.underline < metrics.descent)
        #expect(lines.strikethrough < 0 && -lines.strikethrough < metrics.ascent / 2)
    }

    @Test func patternsBreakTheLineIntoDashes() {
        let solid = TextMeasurer.decorationDashes(length: 100, thickness: 2, pattern: .solid)
        #expect(solid.count == 1 && solid[0].start == 0 && solid[0].end == 100)
        let dashes = TextMeasurer.decorationDashes(length: 100, thickness: 2, pattern: .dash)
        #expect(dashes.count > 5)
        #expect(dashes.first?.start == 0)
        #expect(dashes.allSatisfy { $0.end <= 100 && $0.end > $0.start })
        // On 8, off 4.
        #expect(dashes[1].start == 12 && dashes[0].end == 8)
        let dots = TextMeasurer.decorationDashes(length: 100, thickness: 2, pattern: .dot)
        #expect(dots.count > dashes.count)
        #expect(TextMeasurer.decorationDashes(length: 0, thickness: 2, pattern: .dash).isEmpty)
    }
}
