//
//  TextDrawTests.swift
//  NucleantUITests
//
//  A text command carries the lines layout broke the text into, as they
//  are — drawn without being joined into one string and split again.
//

import Testing
@testable import NucleantUI

@MainActor
@Suite
struct TextDrawTests {

    private func texts<V: View>(_ view: V, width: Double) -> [TextDraw] {
        OffscreenRender(environment: EnvironmentValues())
            .list(of: view, size: Size(width: width, height: 400))
            .commands
            .compactMap { if case .text(let draw) = $0 { draw } else { nil } }
    }

    @Test func aWrappedTextCarriesItsLines() {
        let string = "A label long enough to need more than one line here"
        let width = TextMeasurer.width(of: "A label long enough", font: .body) + 4
        guard let draw = texts(Text(string).frame(width: width), width: 400).first else {
            Issue.record("no text")
            return
        }
        #expect(draw.lines.count > 1)
        #expect(draw.lines.allSatisfy { !$0.contains("\n") })
        #expect(draw.string == draw.lines.joined(separator: "\n"))
        #expect(draw.lines.joined(separator: " ") == string, "every word, in its line")
    }

    @Test func aDrawMadeFromAStringHasItsLines() {
        var draw = TextDraw(string: "one\n\nthree", frame: .zero, font: .body, color: .black)
        #expect(draw.lines == ["one", "", "three"])
        draw.string = "single"
        #expect(draw.lines == ["single"])
    }
}
