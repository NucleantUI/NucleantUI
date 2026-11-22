//
//  PickerTests.swift
//  NucleantUITests
//
//  A picker made without a label, or with a blank one, is the control
//  alone: at the leading edge of the row it is in, as wide as the control
//  and no wider, in every style. A picker with a label still keeps the room
//  between the label and the control.
//

import Testing
@testable import NucleantUI

/// What a probe's picker has for a label.
enum PickerLabelKind {
    /// `Picker(selection:content:)`.
    case none
    /// `Picker("", selection:content:)`.
    case emptyTitle
    /// `Picker(selection:content:label: { EmptyView() })`.
    case emptyView
    /// `Picker("Choice", …).labelsHidden()`: the control alone, to compare
    /// with.
    case hidden
    /// `Picker("Choice", …)`.
    case titled
}

/// A picker in the top leading corner of the window, logging its
/// window-space frame as `"x w×h"`.
@View
struct PickerLabelProbe<Style: PickerStyle> {
    let log: Log
    let kind: PickerLabelKind
    let style: Style

    @State private var choice = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            picker
                .pickerStyle(style)
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var picker: some View {
        if kind == .none {
            Picker(selection: $choice) { options }
        } else if kind == .emptyTitle {
            Picker("", selection: $choice) { options }
        } else if kind == .emptyView {
            Picker(selection: $choice) { options } label: { EmptyView() }
        } else if kind == .hidden {
            Picker("Choice", selection: $choice) { options }
                .labelsHidden()
        } else {
            Picker("Choice", selection: $choice) { options }
        }
    }

    private var options: some View {
        ForEach([1, 2, 3], id: \.self) { value in
            Text("Option \(value)")
        }
    }
}

/// Parses `"x w×h"`.
private func parse(_ entry: String) -> (x: Int, width: Int, height: Int) {
    let parts = entry.split(separator: " ")
    let size = parts[1].split(separator: "×")
    return (Int(parts[0])!, Int(size[0])!, Int(size[1])!)
}

extension HostedViews {
    @MainActor
    @Suite
    struct PickerTests {
        private static let window = Size(width: 400, height: 300)

        /// The picker's frame, for a label of `kind` in `style`.
        private func frame<Style: PickerStyle>(
            _ kind: PickerLabelKind,
            _ style: Style
        ) -> (x: Int, width: Int, height: Int) {
            let log = Log()
            _ = Harness(PickerLabelProbe(log: log, kind: kind, style: style), size: Self.window)
            return parse(log.take().last!)
        }

        @Test func aPickerWithoutALabelIsTheControlAloneAtTheLeadingEdge() {
            let control = frame(.hidden, .menu)
            let unlabeled = frame(.none, .menu)
            #expect(unlabeled.x == 0)
            #expect(unlabeled.width == control.width)
            #expect(unlabeled.height == control.height)
            #expect(unlabeled.width < Int(Self.window.width))
        }

        @Test func anEmptyTitleTakesNoRoom() {
            let control = frame(.hidden, .menu)
            let empty = frame(.emptyTitle, .menu)
            #expect(empty.x == 0)
            #expect(empty.width == control.width)
            #expect(empty.height == control.height)
        }

        @Test func anEmptyViewLabelTakesNoRoom() {
            let control = frame(.hidden, .menu)
            let empty = frame(.emptyView, .menu)
            #expect(empty.x == 0)
            #expect(empty.width == control.width)
            #expect(empty.height == control.height)
        }

        @Test func aTitledPickerStillSpansTheRowToItsControl() {
            let control = frame(.hidden, .menu)
            let titled = frame(.titled, .menu)
            #expect(titled.x == 0)
            #expect(titled.width == Int(Self.window.width))
            #expect(titled.width > control.width)
        }

        @Test func segmentedWithoutALabelIsTheSegmentsAlone() {
            let control = frame(.hidden, .segmented)
            for kind in [PickerLabelKind.none, .emptyTitle, .emptyView] {
                let unlabeled = frame(kind, .segmented)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == control.width)
                #expect(unlabeled.height == control.height)
            }
        }

        @Test func inlineWithoutALabelHasNoLineAboveTheRows() {
            let control = frame(.hidden, .inline)
            for kind in [PickerLabelKind.none, .emptyTitle, .emptyView] {
                let unlabeled = frame(kind, .inline)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == control.width)
                #expect(unlabeled.height == control.height)
            }
            #expect(frame(.titled, .inline).height > control.height)
        }

        @Test func radioGroupWithoutALabelIsTheButtonsAlone() {
            let control = frame(.hidden, .radioGroup)
            for kind in [PickerLabelKind.none, .emptyTitle, .emptyView] {
                let unlabeled = frame(kind, .radioGroup)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == control.width)
                #expect(unlabeled.height == control.height)
            }
            #expect(frame(.titled, .radioGroup).width > control.width)
        }
    }
}
