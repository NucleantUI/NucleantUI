//
//  StepperTests.swift
//  NucleantUITests
//
//  A stepper made without a label, or with a blank one, is the − / +
//  buttons alone: at the leading edge of the row it is in, as wide as the
//  buttons and no wider — and so, after a spacer in a row, on the trailing
//  edge. A stepper with a label still keeps the room between the label and
//  the buttons.
//

import Testing
@testable import NucleantUI

/// What a probe's stepper has for a label.
enum StepperLabelKind {
    /// `Stepper(value:in:)`.
    case none
    /// `Stepper(value:)`.
    case noneUnbounded
    /// `Stepper(onIncrement:onDecrement:)`.
    case noneActions
    /// `Stepper("", value:in:)`.
    case emptyTitle
    /// `Stepper(value:in:label: { EmptyView() })`.
    case emptyView
    /// `Stepper(value:in:label: { Text("Value") }).labelsHidden()`: the
    /// buttons alone, to compare with.
    case hidden
    /// `Stepper(value:in:label: { Text("Value") })`.
    case titled
}

/// A stepper in the top leading corner of the window, logging its
/// window-space frame as `"x w×h"`.
@View
struct StepperLabelProbe {
    let log: Log
    let kind: StepperLabelKind

    @State private var value = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepper
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var stepper: some View {
        if kind == .none {
            Stepper(value: $value, in: 0...10)
        } else if kind == .noneUnbounded {
            Stepper(value: $value)
        } else if kind == .noneActions {
            Stepper(onIncrement: { value += 1 }, onDecrement: { value -= 1 })
        } else if kind == .emptyTitle {
            Stepper("", value: $value, in: 0...10)
        } else if kind == .emptyView {
            Stepper(value: $value, in: 0...10) { EmptyView() }
        } else if kind == .hidden {
            Stepper(value: $value, in: 0...10) { Text("Value") }
                .labelsHidden()
        } else {
            Stepper(value: $value, in: 0...10) { Text("Value") }
        }
    }
}

/// A row with a text on the leading edge, a spacer, then a stepper with no
/// label, logging the stepper's frame as `"x w×h"`.
@View
struct StepperRowProbe {
    let log: Log

    @State private var value = 5

    var body: some View {
        HStack(spacing: 0) {
            Text("Copies")
            Spacer()
            Stepper(value: $value, in: 0...10)
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    struct StepperTests {
        private static let window = Size(width: 400, height: 300)

        /// The stepper's frame, for a label of `kind`.
        private func frame(_ kind: StepperLabelKind) -> (x: Int, width: Int, height: Int) {
            let log = Log()
            _ = Harness(StepperLabelProbe(log: log, kind: kind), size: Self.window)
            return parse(log.take().last!)
        }

        @Test func aStepperWithoutALabelIsTheButtonsAloneAtTheLeadingEdge() {
            let buttons = frame(.hidden)
            #expect(buttons.width < Int(Self.window.width))
            for kind in [StepperLabelKind.none, .noneUnbounded, .noneActions] {
                let unlabeled = frame(kind)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == buttons.width)
                #expect(unlabeled.height == buttons.height)
            }
        }

        @Test func aBlankLabelTakesNoRoom() {
            let buttons = frame(.hidden)
            for kind in [StepperLabelKind.emptyTitle, .emptyView] {
                let blank = frame(kind)
                #expect(blank.x == 0)
                #expect(blank.width == buttons.width)
                #expect(blank.height == buttons.height)
            }
        }

        @Test func aTitledStepperStillSpansTheRowToItsButtons() {
            let titled = frame(.titled)
            #expect(titled.x == 0)
            #expect(titled.width == Int(Self.window.width))
            #expect(titled.width > frame(.hidden).width)
        }

        @Test func afterASpacerTheButtonsSitOnTheTrailingEdge() {
            let buttons = frame(.hidden)
            let log = Log()
            _ = Harness(StepperRowProbe(log: log), size: Self.window)
            let row = parse(log.take().last!)
            #expect(row.width == buttons.width)
            #expect(row.x + row.width == Int(Self.window.width))
        }
    }
}
