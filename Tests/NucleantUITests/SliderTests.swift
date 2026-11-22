//
//  SliderTests.swift
//  NucleantUITests
//
//  A slider made without a label, or with a blank one, keeps no room for
//  it: the track starts at the labels there are. A blank value label is
//  left out the same way. Measured at the slider's ideal width, where the
//  track is its own fixed width and every gap shows.
//

import Testing
@testable import NucleantUI

/// What a probe's slider has for labels.
enum SliderLabelKind {
    /// `Slider(value:)`.
    case none
    /// `Slider(value:in:minimumValueLabel:maximumValueLabel:)`.
    case noneWithValueLabels
    /// `Slider(value:in:step:minimumValueLabel:maximumValueLabel:)`.
    case noneWithValueLabelsStepped
    /// `Slider(value:label: { Text("") })`.
    case emptyTitle
    /// `Slider(value:in:step:label: { Text("") })`.
    case emptyTitleStepped
    /// `Slider(value:label: { EmptyView() })`.
    case emptyView
    /// `Slider(value:label: { Text("Volume") })` with `Text("")` value
    /// labels, label hidden.
    case blankValueLabels
    /// `Slider(value:label: { Text("Volume") }).labelsHidden()`: the track
    /// alone, to compare with.
    case hidden
    /// The same with value labels, label hidden.
    case hiddenWithValueLabels
    /// `Slider(value:label: { Text("Volume") })`.
    case titled
}

/// A slider at its ideal width in the top leading corner of the window,
/// logging its window-space frame as `"x w×h"`.
@View
struct SliderLabelProbe {
    let log: Log
    let kind: SliderLabelKind

    @State private var value = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            slider
                .fixedSize(horizontal: true, vertical: false)
                .onGeometryChange(for: Rect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    log("\(Int(frame.minX)) \(Int(frame.width))×\(Int(frame.height))")
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var slider: some View {
        if kind == .none {
            Slider(value: $value)
        } else if kind == .noneWithValueLabels {
            Slider(value: $value) {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }
        } else if kind == .noneWithValueLabelsStepped {
            Slider(value: $value, in: 0...1, step: 0.1) {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }
        } else if kind == .emptyTitle {
            Slider(value: $value) { Text("") }
        } else if kind == .emptyTitleStepped {
            Slider(value: $value, in: 0...1, step: 0.1) { Text("") }
        } else if kind == .emptyView {
            Slider(value: $value) { EmptyView() }
        } else if kind == .blankValueLabels {
            Slider(value: $value) {
                Text("Volume")
            } minimumValueLabel: {
                Text("")
            } maximumValueLabel: {
                Text("")
            }
            .labelsHidden()
        } else if kind == .hidden {
            Slider(value: $value) { Text("Volume") }
                .labelsHidden()
        } else if kind == .hiddenWithValueLabels {
            Slider(value: $value) {
                Text("Volume")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }
            .labelsHidden()
        } else {
            Slider(value: $value) { Text("Volume") }
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
    struct SliderTests {
        private static let window = Size(width: 400, height: 300)

        /// The slider's frame at its ideal width, for labels of `kind`.
        private func frame(_ kind: SliderLabelKind) -> (x: Int, width: Int, height: Int) {
            let log = Log()
            _ = Harness(SliderLabelProbe(log: log, kind: kind), size: Self.window)
            return parse(log.take().last!)
        }

        @Test func aSliderWithoutALabelIsTheTrackAlone() {
            let track = frame(.hidden)
            let unlabeled = frame(.none)
            #expect(unlabeled.x == 0)
            #expect(unlabeled.width == track.width)
            #expect(unlabeled.height == track.height)
        }

        @Test func valueLabelsWithoutALabelKeepNoRoomForIt() {
            let labeled = frame(.hiddenWithValueLabels)
            #expect(labeled.width > frame(.hidden).width)
            for kind in [SliderLabelKind.noneWithValueLabels, .noneWithValueLabelsStepped] {
                let unlabeled = frame(kind)
                #expect(unlabeled.x == 0)
                #expect(unlabeled.width == labeled.width)
                #expect(unlabeled.height == labeled.height)
            }
        }

        @Test func aBlankLabelTakesNoRoom() {
            let track = frame(.hidden)
            for kind in [SliderLabelKind.emptyTitle, .emptyTitleStepped, .emptyView] {
                let blank = frame(kind)
                #expect(blank.x == 0)
                #expect(blank.width == track.width)
            }
        }

        @Test func blankValueLabelsTakeNoRoom() {
            #expect(frame(.blankValueLabels).width == frame(.hidden).width)
        }

        @Test func aTitledSliderStillDrawsItsLabel() {
            #expect(frame(.titled).width > frame(.hidden).width)
        }
    }
}
