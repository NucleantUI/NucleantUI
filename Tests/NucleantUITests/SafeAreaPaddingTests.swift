//
//  SafeAreaPaddingTests.swift
//  NucleantUITests
//
//  `.safeAreaPadding`: a scroll view under it keeps its frame and insets
//  its content; any other view is padded.
//

import Foundation
import Testing
@testable import NucleantUI

/// Eight 150-wide cards 10 apart in a sideways scroll view, view aligned,
/// with 20 points of safe area padding each side.
@View
struct PaddedCardStrip {
    let probe: ScrollProbe

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(0..<8) { _ in
                    Color.orange.frame(width: 150, height: 100)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minX } action: { probe.leading = $0 }
        }
        .onGeometryChange(for: Double.self) { $0.frame(in: .global).width } action: { probe.width = $0 }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal, 20)
    }
}

/// A scroll view under a frame, padded at the top.
@View
struct FramedPaddedScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            Color.blue.frame(height: 1000)
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .frame(height: 150)
        .safeAreaPadding(.top, 10)
    }
}

/// A plain view padded.
@View
struct PaddedColor {
    let probe: ScrollProbe

    var body: some View {
        Color.red
            .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { frame in
                probe.leading = frame.minX
                probe.top = frame.minY
                probe.width = frame.width
            }
            .safeAreaPadding(10)
    }
}

/// A sideways strip in a padded scroll view.
@View
struct PaddedOuterScroll {
    let probe: ScrollProbe

    var body: some View {
        ScrollView {
            ScrollView(.horizontal) {
                Color.green.frame(width: 1000, height: 100)
                    .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView(axis: .horizontal)).minX } action: { probe.leading = $0 }
            }
        }
        .safeAreaPadding(30)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct SafeAreaPaddings {

        @Test func aScrollViewKeepsItsFrameAndInsetsItsContent() {
            let probe = ScrollProbe()
            _ = Harness(PaddedCardStrip(probe: probe))
            #expect(probe.width == 200, "the scroll view is as wide as the window")
            #expect(probe.leading == 20, "its content starts 20 in")
        }

        @Test func viewAlignedCardsComeToRestInsideThePadding() async {
            let probe = ScrollProbe()
            let harness = Harness(PaddedCardStrip(probe: probe))
            harness.host.scrollsOnDrag = true

            harness.drag(from: Point(x: 180, y: 50), by: Point(x: -100, y: 0))
            await harness.frames(50)
            // The second card, at 160 in the content, rests 20 in.
            #expect(probe.leading == -140)
        }

        @Test func throughTheModifiersOverItItIsStillTheScrollViewThatTakesIt() {
            let probe = ScrollProbe()
            _ = Harness(FramedPaddedScroll(probe: probe))
            #expect(probe.top == 10)
        }

        @Test func anyOtherViewIsPadded() {
            let probe = ScrollProbe()
            _ = Harness(PaddedColor(probe: probe))
            #expect(probe.leading == 10)
            #expect(probe.top == 10)
            #expect(probe.width == 180)
        }

        @Test func aScrollViewInsideTheOneItPadsIsNotPadded() {
            let probe = ScrollProbe()
            _ = Harness(PaddedOuterScroll(probe: probe))
            #expect(probe.leading == 0)
        }
    }
}
