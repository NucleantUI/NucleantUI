//
//  TextFieldTests.swift
//  NucleantUITests
//
//  A field made without a label is the same field: as big as one with a
//  title, and it takes typing into its text or, through a format, into its
//  value. Its placeholder is the prompt when it has one, and nothing when
//  it has none — a label is only ever the placeholder, so it takes no room
//  of its own.
//

import Foundation
import Testing
@testable import NucleantUI

/// What a probe's field is made with.
enum TextFieldLabelKind {
    /// `TextField(text:)`.
    case none
    /// `TextField(text:prompt:)`.
    case prompt
    /// `TextField(value:format:)`, the value optional.
    case optionalValue
    /// `TextField(value:formatter:)`.
    case formatter
    /// `TextField("", text:)`.
    case emptyTitle
    /// `TextField(text:label: { EmptyView() })`.
    case emptyView
    /// `TextField("Name", text:)`.
    case titled
}

/// A field in the top leading corner of the window, logging its
/// window-space frame as `"x w×h"`.
@View
struct TextFieldLabelProbe {
    let log: Log
    let kind: TextFieldLabelKind

    @State private var text = ""
    @State private var count: Int? = nil
    @State private var amount = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var field: some View {
        if kind == .none {
            TextField(text: $text)
        } else if kind == .prompt {
            TextField(text: $text, prompt: Text("Search"))
        } else if kind == .optionalValue {
            TextField(value: $count, format: .number)
        } else if kind == .formatter {
            TextField(value: $amount, formatter: NumberFormatter())
        } else if kind == .emptyTitle {
            TextField("", text: $text)
        } else if kind == .emptyView {
            TextField(text: $text) { EmptyView() }
        } else {
            TextField("Name", text: $text)
        }
    }
}

/// A label-less field over a string, 200 × 200, logging each new text.
@View
struct UnlabeledTextEntry {
    let log: Log

    @State private var text = ""

    var body: some View {
        TextField(text: $text, prompt: Text("Search"))
            .frame(width: 200, height: 200)
            .onChange(of: text) { _, new in log("text \(new)") }
    }
}

/// A label-less field over a number, 200 × 200, logging each new value.
@View
struct UnlabeledValueEntry {
    let log: Log

    @State private var count = 5

    var body: some View {
        TextField(value: $count, format: .number)
            .frame(width: 200, height: 200)
            .onChange(of: count) { _, new in log("count \(new)") }
    }
}

/// Parses `"x w×h"`.
private func parse(_ entry: String) -> (x: Int, width: Int, height: Int) {
    let parts = entry.split(separator: " ")
    let size = parts[1].split(separator: "×")
    return (Int(parts[0])!, Int(size[0])!, Int(size[1])!)
}

/// The key that types a 7.
private let sevenKey: UInt16 = 0x1A

extension HostedViews {
    @MainActor
    @Suite
    struct TextFieldTests {
        private static let window = Size(width: 400, height: 300)

        /// The field's frame, made as `kind` says.
        private func frame(_ kind: TextFieldLabelKind) -> (x: Int, width: Int, height: Int) {
            let log = Log()
            _ = Harness(TextFieldLabelProbe(log: log, kind: kind), size: Self.window)
            return parse(log.take().last!)
        }

        @Test func aFieldWithoutALabelIsAsBigAsOneWithATitle() {
            let titled = frame(.titled)
            for kind in [TextFieldLabelKind.none, .prompt, .optionalValue, .formatter, .emptyTitle, .emptyView] {
                let unlabeled = frame(kind)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == titled.width)
                #expect(unlabeled.height == titled.height)
            }
        }

        @Test func typingGoesIntoTheTextOfAFieldWithoutALabel() async {
            let log = Log()
            let harness = Harness(UnlabeledTextEntry(log: log))
            await harness.tap(center)
            await harness.key(KeyCode.x, "x")
            #expect(log.take().last == "text x")
        }

        @Test func typingGoesIntoTheValueOfAFieldWithoutALabel() async {
            let log = Log()
            let harness = Harness(UnlabeledValueEntry(log: log))
            await harness.tap(center)
            await harness.key(sevenKey, "7")
            #expect(log.take().last == "count 57")
        }
    }
}
