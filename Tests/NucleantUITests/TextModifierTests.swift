//
//  TextModifierTests.swift
//  NucleantUITests
//
//  The text modifiers, through the views that use them: the modifier nearest
//  a `Text` wins, a view's kerning, tracking, offset and lines are defaults
//  a text's own replace, the environment values and their clamps, the case
//  changed with the locale, and what ends up in the text's draw command.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
@Suite
struct TextModifierTests {

    static let sentence = "The quick brown fox jumps over the lazy dog again and again"

    /// The text draws `view` makes when laid out at `size`, in a stack so
    /// it is placed at its own size rather than stretched to the whole.
    private func texts<V: View>(_ view: V, size: Size = Size(width: 300, height: 300)) -> [TextDraw] {
        OffscreenRender(environment: EnvironmentValues()).list(of: VStack { view }, size: size).commands.compactMap {
            if case .text(let draw) = $0 { return draw }
            return nil
        }
    }

    private func text<V: View>(_ view: V, size: Size = Size(width: 300, height: 300)) -> TextDraw? {
        texts(view, size: size).first
    }

    private var bodyLineHeight: Double { TextMeasurer.lineMetrics(for: .body).lineHeight }

    // MARK: - The nearest modifier wins

    @Test func theInnermostFontWins() {
        #expect(text(Text("a").font(.title).font(.caption))?.font == .title)
        #expect(text(Text("a").fontWeight(.bold).fontWeight(.light))?.font.weight == .bold)
        #expect(text(Text("a").foregroundColor(.red).foregroundColor(.blue))?.color == Color.red)
    }

    @Test func theInnermostSpacingWins() {
        #expect(text(Text("a").kerning(1).kerning(8))?.letterSpacing == 1)
        #expect(text(Text("a").tracking(2).tracking(9))?.letterSpacing == 2)
        #expect(text(Text(Self.sentence).lineLimit(1).lineLimit(3).frame(width: 120))?.string.contains("\n") == false)
    }

    @Test func aTextsOwnValueBeatsTheViewsAroundIt() {
        #expect(text(VStack { Text("a").kerning(1) }.kerning(8))?.letterSpacing == 1)
        #expect(text(VStack { Text("a") }.kerning(8))?.letterSpacing == 8)
        #expect(text(VStack { Text("a").font(.caption) }.font(.title))?.font == .caption)
        let corner = Size(width: 100, height: 100)
        #expect(text(VStack { Text("a").baselineOffset(-2) }.baselineOffset(-9).frame(width: 100, height: 100, alignment: .topLeading), size: corner)?.frame.minY == 2)
        #expect(text(VStack { Text("a") }.baselineOffset(-9).frame(width: 100, height: 100, alignment: .topLeading), size: corner)?.frame.minY == 9)
    }

    @Test func trackingWinsOverKerning() {
        #expect(text(Text("a").kerning(3).tracking(1))?.letterSpacing == 1)
        #expect(text(Text("a").tracking(1).kerning(3))?.letterSpacing == 1)
        // A view's tracking still beats the text's own kerning.
        #expect(text(VStack { Text("a").kerning(5) }.tracking(2))?.letterSpacing == 2)
    }

    // MARK: - Environment values

    @Test func defaults() {
        let values = EnvironmentValues()
        #expect(values.truncationMode == .tail)
        #expect(values.lineSpacing == 0)
        #expect(values.allowsTightening == false)
        #expect(values.minimumScaleFactor == 1)
        #expect(values.textCase == nil)
    }

    @Test func aMinimumScaleOutsideZeroToOneIsOne() {
        var values = EnvironmentValues()
        for (factor, stored) in [(0.5, 0.5), (1, 1), (0, 1), (-1, 1), (2, 1), (0.01, 0.01)] {
            values.minimumScaleFactor = factor
            #expect(values.minimumScaleFactor == stored, "\(factor)")
        }
    }

    @Test func viewModifiersSetTheirValues() {
        let draw = text(
            Text(Self.sentence)
                .lineSpacing(7)
                .frame(width: 120)
        )
        #expect(draw?.lineSpacing == 7)
        let lines = draw?.string.split(separator: "\n").count ?? 0
        #expect(lines > 1)
        #expect(draw.map { $0.frame.height } == Double(lines) * bodyLineHeight + Double(lines - 1) * 7)
    }

    // MARK: - Case

    @Test func textCaseChangesTheCaseBeforeMeasuring() {
        #expect(text(VStack { Text("straße") }.textCase(.uppercase))?.string == "STRASSE")
        #expect(text(Text("Hello World").textCase(.lowercase))?.string == "hello world")
        #expect(text(Text("Hello").textCase(nil))?.string == "Hello")
        let upper = text(VStack { Text("straße") }.textCase(.uppercase))
        #expect(upper.map(\.frame.width) == TextMeasurer.width(of: "STRASSE", font: .body))
    }

    @Test func textCaseUsesTheEnvironmentsLocale() {
        let turkish = text(VStack { Text("istanbul") }.textCase(.uppercase).environment(\.locale, Locale(identifier: "tr_TR")))
        #expect(turkish?.string == "İSTANBUL")
        let english = text(VStack { Text("istanbul") }.textCase(.uppercase).environment(\.locale, Locale(identifier: "en_US")))
        #expect(english?.string == "ISTANBUL")
    }

    // MARK: - Lines

    @Test func aLineLimitOfZeroIsOneLine() {
        let draw = text(Text(Self.sentence).lineLimit(0).frame(width: 120))
        #expect(draw?.string.contains("\n") == false)
        #expect(draw?.string.hasSuffix("…") == true)
    }

    @Test func aTextKeepsRoomForItsLowerLimit() {
        #expect(text(Text("A").lineLimit(3, reservesSpace: true))?.frame.height == 3 * bodyLineHeight)
        #expect(text(Text("A").lineLimit(2...4))?.frame.height == 2 * bodyLineHeight)
        #expect(text(Text("A").lineLimit(3...))?.frame.height == 3 * bodyLineHeight)
        #expect(text(Text("A").lineLimit(...3))?.frame.height == bodyLineHeight)
        #expect(text(Text("A").lineLimit(3, reservesSpace: false))?.frame.height == bodyLineHeight)
    }

    @Test func aRangeReplacesTheOneAroundIt() {
        // The inner range wins whole: reserved lines come from it alone.
        #expect(text(VStack { Text("A").lineLimit(3...) }.lineLimit(...5))?.frame.height == 3 * bodyLineHeight)
        #expect(text(VStack { Text("A").lineLimit(...5) }.lineLimit(3...))?.frame.height == bodyLineHeight)
    }

    @Test func aTextKeepsTheIndentOfEachLine() {
        // Issue #26: whether a line wraps (200) or none does (560).
        let json = "{\n    \"name\": \"a value long enough to wrap\",\n    \"id\": 7\n}"
        for width in [200.0, 560] {
            let draw = text(
                Text(json).font(.system(size: 15, design: .monospaced)).frame(width: width, alignment: .leading),
                size: Size(width: 600, height: 300)
            )
            #expect(draw?.string.contains("\n    \"name\": ") == true, "\(width)")
            #expect(draw?.string.hasSuffix("\n    \"id\": 7\n}") == true, "\(width)")
        }
    }

    @Test func aHeightLimitsTheLinesShown() {
        let draw = text(Text(Self.sentence).frame(width: 120, height: 2 * bodyLineHeight + 1))
        #expect(draw?.string.split(separator: "\n").count == 2)
        #expect(draw?.string.hasSuffix("…") == true)
    }

    @Test func eachTruncationModeCutsTheLastLine() {
        let tail = text(Text(Self.sentence).lineLimit(1).truncationMode(.tail).frame(width: 150))?.string
        let head = text(Text(Self.sentence).lineLimit(1).truncationMode(.head).frame(width: 150))?.string
        let middle = text(Text(Self.sentence).lineLimit(1).truncationMode(.middle).frame(width: 150))?.string
        #expect(tail?.hasPrefix("The") == true && tail?.hasSuffix("…") == true)
        #expect(head?.hasPrefix("…") == true && head?.hasSuffix("again") == true)
        #expect(middle?.hasPrefix("The") == true && middle?.hasSuffix("again") == true && middle?.contains("…") == true)
    }

    @Test func tighteningAndScalingReachTheDraw() {
        let natural = TextMeasurer.width(of: Self.sentence, font: .body)
        let tight = text(Text(Self.sentence).lineLimit(1).allowsTightening(true).frame(width: natural * 0.985), size: Size(width: 1000, height: 300))
        #expect(tight?.string == Self.sentence)
        #expect((tight?.lastLineTightening ?? 0) < 0)

        let scaled = text(Text(Self.sentence).lineLimit(1).minimumScaleFactor(0.3).frame(width: natural / 2), size: Size(width: 1000, height: 300))
        #expect(scaled?.string == Self.sentence)
        #expect((scaled?.font.size ?? 99) < Font.body.size * 0.55)
        #expect((scaled?.frame.height ?? 99) < bodyLineHeight)
    }

    @Test func theBaselineOffsetMovesTheGlyphsInsideAGrownBox() {
        let lineHeight = bodyLineHeight
        let corner = Size(width: 200, height: 100)
        let down = text(Text("Hello").baselineOffset(-10).frame(width: 200, height: 100, alignment: .topLeading), size: corner)
        #expect(down?.frame.minY == 10)
        #expect(down?.frame.height == lineHeight)
        let up = text(Text("Hello").baselineOffset(10).frame(width: 200, height: 100, alignment: .topLeading), size: corner)
        #expect(up?.frame.minY == 0)
        #expect(up?.frame.height == lineHeight)
    }

    // MARK: - Underline and strikethrough

    @Test func underlineAndStrikethroughOnTheText() {
        #expect(text(Text("a").underline())?.underline == .single)
        #expect(text(Text("a").underline(color: .red))?.underline == Text.LineStyle(color: .red))
        #expect(text(Text("a").underline(pattern: .dash))?.underline?.pattern == .dash)
        #expect(text(Text("a").strikethrough())?.strikethrough == .single)
        #expect(text(Text("a").strikethrough(pattern: .dot, color: .blue))?.strikethrough == Text.LineStyle(pattern: .dot, color: .blue))
        #expect(text(Text("a"))?.underline == nil)
        #expect(text(Text("a").underline(false))?.underline == nil)
    }

    @Test func aViewsLinesAreDefaultsTheTextCanTurnOff() {
        #expect(text(VStack { Text("a") }.underline(pattern: .dashDot))?.underline?.pattern == .dashDot)
        #expect(text(VStack { Text("a").underline(false) }.underline())?.underline == nil)
        #expect(text(VStack { Text("a").strikethrough(color: .green) }.strikethrough(color: .red))?.strikethrough?.color == Color.green)
        #expect(text(VStack { Text("a") }.underline().underline(false))?.underline == .single)
    }
}

// MARK: - Settings changed further out

/// What the view text settings are where it is built.
@View
private struct SettingsReader {
    let log: Log
    @Environment(\.lineSpacing) private var lineSpacing
    @Environment(\.truncationMode) private var truncationMode

    var body: some View {
        let _ = log("spacing \(lineSpacing) \(truncationMode)")
        Color.blue
            .frame(width: 200, height: 200)
    }
}

/// An outer line spacing that changes on a tap, over an inner truncation
/// mode set once: the two settings share one environment value.
@View
private struct SettingsHost {
    let log: Log
    @State private var spacing = 2.0

    var body: some View {
        VStack(spacing: 0) {
            SettingsReader(log: log)
                .truncationMode(.head)
        }
        .lineSpacing(spacing)
        .onTapGesture { spacing = 9 }
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct TextSettingsChanges {

        /// A setting changed further out reaches past a modifier nearer the
        /// view that set another one, and the nearer one keeps its own.
        @Test func anOuterChangeReachesPastAnInnerSetting() async {
            let log = Log()
            let harness = Harness(SettingsHost(log: log))
            #expect(log.take() == ["spacing 2.0 head"])
            await harness.tap(center)
            #expect(log.take() == ["spacing 9.0 head"])
        }
    }
}
