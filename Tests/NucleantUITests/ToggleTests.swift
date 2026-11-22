//
//  ToggleTests.swift
//  NucleantUITests
//
//  A toggle made without a label, or with a blank one, is the switch or
//  box alone: at the leading edge of the row it is in, as wide as the
//  control and no wider — and so, after a spacer in a row, on the trailing
//  edge. That holds through a style that forwards the toggle with
//  `Toggle(configuration)`. A toggle with a label still draws it.
//

import Testing
@testable import NucleantUI

/// What a probe's toggle has for a label.
enum ToggleLabelKind {
    /// `Toggle(isOn:)`.
    case none
    /// `Toggle("", isOn:)`.
    case emptyTitle
    /// `Toggle(isOn:label: { EmptyView() })`.
    case emptyView
    /// `Toggle(isOn:)` drawn by a style that forwards it with
    /// `Toggle(configuration)`.
    case forwarded
    /// `Toggle(isOn:label: { Text("Power") }).labelsHidden()`: the control
    /// alone, to compare with.
    case hidden
    /// `Toggle(isOn:label: { Text("Power") })`.
    case titled
}

/// A style that hands the toggle on to `inner`, as a style that only
/// adjusts another one does.
struct ForwardedToggleStyle<Inner: ToggleStyle>: ToggleStyle {
    let inner: Inner

    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(inner)
    }
}

/// A toggle in the top leading corner of the window, logging its
/// window-space frame as `"x w×h"`.
@View
struct ToggleLabelProbe<Style: ToggleStyle> {
    let log: Log
    let kind: ToggleLabelKind
    let style: Style

    @State private var isOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggle
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var toggle: some View {
        if kind == .forwarded {
            Toggle(isOn: $isOn)
                .toggleStyle(ForwardedToggleStyle(inner: style))
        } else {
            plain.toggleStyle(style)
        }
    }

    @ViewBuilder
    private var plain: some View {
        if kind == .none {
            Toggle(isOn: $isOn)
        } else if kind == .emptyTitle {
            Toggle("", isOn: $isOn)
        } else if kind == .emptyView {
            Toggle(isOn: $isOn) { EmptyView() }
        } else if kind == .hidden {
            Toggle(isOn: $isOn) { Text("Power") }
                .labelsHidden()
        } else {
            Toggle(isOn: $isOn) { Text("Power") }
        }
    }
}

/// A row with a text on the leading edge, a spacer, then a switch with no
/// label, logging the switch's frame as `"x w×h"`.
@View
struct SwitchRowProbe {
    let log: Log

    @State private var isOn = true

    var body: some View {
        HStack(spacing: 0) {
            Text("Wi-Fi")
            Spacer()
            Toggle(isOn: $isOn)
                .toggleStyle(.switch)
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
    struct ToggleTests {
        private static let window = Size(width: 400, height: 300)
        private static let unlabeled: [ToggleLabelKind] = [.none, .emptyTitle, .emptyView, .forwarded]

        /// The toggle's frame, for a label of `kind` in `style`.
        private func frame<Style: ToggleStyle>(
            _ kind: ToggleLabelKind,
            _ style: Style
        ) -> (x: Int, width: Int, height: Int) {
            let log = Log()
            _ = Harness(ToggleLabelProbe(log: log, kind: kind, style: style), size: Self.window)
            return parse(log.take().last!)
        }

        @Test func aSwitchWithoutALabelIsTheSwitchAloneAtTheLeadingEdge() {
            let control = frame(.hidden, .switch)
            #expect(control.width < Int(Self.window.width))
            for kind in Self.unlabeled {
                let unlabeled = frame(kind, .switch)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == control.width)
                #expect(unlabeled.height == control.height)
            }
        }

        @Test func aTitledSwitchStillSpansTheRowToItsSwitch() {
            let titled = frame(.titled, .switch)
            #expect(titled.x == 0)
            #expect(titled.width == Int(Self.window.width))
            #expect(titled.width > frame(.hidden, .switch).width)
        }

        @Test func aCheckboxWithoutALabelIsTheBoxAlone() {
            let control = frame(.hidden, .checkbox)
            for kind in Self.unlabeled {
                let unlabeled = frame(kind, .checkbox)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == control.width)
                #expect(unlabeled.height == control.height)
            }
            #expect(frame(.titled, .checkbox).width > control.width)
        }

        @Test func afterASpacerTheSwitchSitsOnTheTrailingEdge() {
            let control = frame(.hidden, .switch)
            let log = Log()
            _ = Harness(SwitchRowProbe(log: log), size: Self.window)
            let row = parse(log.take().last!)
            #expect(row.width == control.width)
            #expect(row.x + row.width == Int(Self.window.width))
        }
    }
}
