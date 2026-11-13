//
//  StackLayoutTests.swift
//  NucleantUITests
//
//  How a stack shares its length, as SwiftUI's do: the least flexible child
//  first — a fixed frame, then the text that can shrink least, then what
//  stretches without end — each offered an equal share of what the ones
//  before it left. The same for the stack views and the stack `Layout`s.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct StackLayoutTests {

    private func commands<V: View>(_ view: V, width: Double, height: Double = 200) -> [DrawCommand] {
        OffscreenRender(environment: EnvironmentValues()).list(of: view, size: Size(width: width, height: height)).commands
    }

    private func shapes<V: View>(_ view: V, width: Double, height: Double = 200) -> [Rect] {
        commands(view, width: width, height: height).compactMap {
            if case .shape(let draw) = $0 { return draw.bounds }
            return nil
        }
    }

    private func texts<V: View>(_ view: V, width: Double, height: Double = 200) -> [TextDraw] {
        commands(view, width: width, height: height).compactMap {
            if case .text(let draw) = $0 { return draw }
            return nil
        }
    }

    private func ideal(_ string: String, font: Font = .body) -> Double {
        TextMeasurer.width(of: string, font: font)
    }

    static let long = "A label long enough to need two lines here"
    static let short = "Short"

    // MARK: - Order

    @Test func aFixedFrameIsSizedBeforeAColor() {
        #expect(shapes(HStack(spacing: 0) { Color.red; Color.blue.frame(width: 50) }, width: 200).map(\.width) == [150, 50])
        #expect(shapes(HStack(spacing: 0) { Color.blue.frame(width: 50); Color.red }, width: 200).map(\.width) == [50, 150])
    }

    @Test func colorsShareEqually() {
        #expect(shapes(HStack(spacing: 0) { Color.red; Color.blue }, width: 200).map(\.width) == [100, 100])
        #expect(shapes(HStack(spacing: 0) { Color.red; Spacer(); Color.blue }, width: 300).map(\.width) == [100, 100])
    }

    @Test func aSpacerGetsWhatTheTextsLeave() {
        let frames = texts(HStack(spacing: 0) { Text("a"); Spacer(); Text("b") }, width: 300).map(\.frame)
        #expect(frames.map(\.width) == [ideal("a"), ideal("b")])
        #expect(frames.first?.minX == 0)
        #expect(frames.last?.maxX == 300)
    }

    @Test func aRowThatFitsPutsEachTextAtItsNaturalWidth() {
        let strings = ["One", "Two words", "And then a third"]
        let width = strings.map { ideal($0) }.reduce(0, +) + 1
        let draws = texts(HStack(spacing: 0) { Text(strings[0]); Text(strings[1]); Text(strings[2]) }, width: width)
        #expect(draws.map(\.string) == strings)
        #expect(draws.map(\.frame.width) == strings.map { ideal($0) })
    }

    @Test func theTextThatCanGiveMostIsSqueezed() {
        // The short text is sized first, whole; the long one wraps into what
        // is left — whichever comes first in the row.
        let width = ideal(Self.long) * 0.75 + ideal(Self.short)
        let longFirst = texts(HStack(spacing: 0) { Text(Self.long); Text(Self.short) }, width: width)
        let shortFirst = texts(HStack(spacing: 0) { Text(Self.short); Text(Self.long) }, width: width)
        for draws in [longFirst, shortFirst] {
            let long = draws.first { $0.string.hasPrefix("A label") }
            let short = draws.first { $0.string == Self.short }
            #expect(short?.frame.width == ideal(Self.short))
            #expect(long?.string.contains("\n") == true)
            // More than an equal half of the row.
            #expect((long?.frame.width ?? 0) > width / 2)
            #expect((long?.frame.width ?? .infinity) <= width - ideal(Self.short))
        }
    }

    @Test func squeezedChipsKeepTheShortLabelsWhole() {
        // The row SwiftUI renders: "Dark", then "Light" sized first, whole,
        // and "Follow the system" wrapped into what they leave. The row is
        // as narrow as keeps the two whole, an equal share each in turn —
        // where sizing in the row's own order cuts "Light".
        let font = Font.system(size: 15)
        let row = HStack(spacing: 8) {
            Text("Follow the system").font(font).padding(horizontal: 10, vertical: 8)
            Text("Light").font(font).padding(horizontal: 10, vertical: 8)
            Text("Dark").font(font).padding(horizontal: 10, vertical: 8)
        }
        let light = ideal("Light", font: font) + 20
        let dark = ideal("Dark", font: font) + 20
        let width = 2 * 8 + max(3 * dark, dark + 2 * light) + 1
        let draws = texts(row, width: width).sorted { $0.frame.minX < $1.frame.minX }
        #expect(draws.map(\.string).dropFirst() == ["Light", "Dark"])
        #expect(draws.first?.string.contains("\n") == true)
        let left = width - 2 * 8 - light - dark
        #expect((draws.first?.frame.width ?? .infinity) <= left - 20)
    }

    @Test func aVStackSizesByFlexibilityToo() {
        #expect(shapes(VStack(spacing: 0) { Color.red; Color.blue.frame(height: 30) }, width: 100, height: 100).map(\.height) == [70, 30])
        let lineHeight = TextMeasurer.lineMetrics(for: .body).lineHeight
        let draws = texts(VStack(spacing: 0) { Color.red; Text("one line") }, width: 100, height: 100)
        #expect(draws.first?.frame.height == lineHeight)
    }

    // MARK: - The stack layouts

    @Test func theLayoutValueSizesAsTheStackDoes() {
        let width = ideal(Self.long) * 0.75 + ideal(Self.short)
        let view = texts(HStack(spacing: 0) { Text(Self.long); Text(Self.short) }, width: width)
        let layout = texts(HStackLayout(spacing: 0) { Text(Self.long); Text(Self.short) }, width: width)
        #expect(layout.map(\.string) == view.map(\.string))
        #expect(layout.map(\.frame) == view.map(\.frame))
        #expect(
            shapes(VStackLayout(spacing: 0) { Color.red; Color.blue.frame(height: 30) }, width: 100, height: 100).map(\.height)
                == [70, 30]
        )
    }
}
