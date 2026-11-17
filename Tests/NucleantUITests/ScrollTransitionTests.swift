//
//  ScrollTransitionTests.swift
//  NucleantUITests
//
//  Scroll transitions: how far in a threshold is, the phases, then rows of
//  a hosted scroll view moved by a transition as they scroll in and out.
//

import Foundation
import Testing
@testable import NucleantUI

struct ScrollTransitionThresholdTests {

    typealias Threshold = ScrollTransitionConfiguration.Threshold

    /// How far into a 200-long container a 50-long view must be.
    private func distance(_ threshold: Threshold) -> Double {
        threshold.distance(container: 200, length: 50)
    }

    @Test func hiddenIsJustOutsideAndVisibleAllTheWayIn() {
        #expect(distance(.hidden) == 0)
        #expect(distance(.visible) == 50)
    }

    @Test(arguments: [(0.5, 25.0), (2, 50), (-1, 0)])
    func visibleByAnAmountIsThatShareOfTheViewClamped(amount: Double, expected: Double) {
        #expect(distance(.visible(amount)) == expected)
    }

    @Test func centeredIsTheViewsMiddleAtTheContainersMiddle() {
        #expect(distance(.centered) == 125)
    }

    @Test func aViewLongerThanTheContainerIsNeverAllInView() {
        #expect(Threshold.visible.distance(container: 200, length: 300) == 200)
    }

    @Test func thresholdsInterpolateAndInset() {
        #expect(distance(Threshold.hidden.interpolated(towards: .visible, amount: 0.25)) == 12.5)
        #expect(distance(Threshold.visible.inset(by: 10)) == 60)
        #expect(distance(Threshold.centered.inset(by: -25)) == 100)
    }
}

struct ScrollTransitionPhaseTests {

    @Test(arguments: [(ScrollTransitionPhase.topLeading, -1.0), (.identity, 0), (.bottomTrailing, 1)])
    func eachPhaseHasItsValue(phase: ScrollTransitionPhase, value: Double) {
        #expect(phase.value == value)
        #expect(phase.isIdentity == (phase == .identity))
    }
}

// MARK: - Hosted

/// Where each row is drawn, by its index.
@MainActor
final class RowProbe {
    var leading: [Int: Double] = [:]
}

/// Twenty rows 50 tall in 200, each moved sideways by its phase: −100
/// coming in at the top, +100 at the bottom, none in view.
@View
struct TransitionedRows {
    let probe: RowProbe
    let configuration: ScrollTransitionConfiguration

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { row in
                    Color.blue.frame(width: 50, height: 50)
                        .onGeometryChange(for: Double.self) { $0.frame(in: .global).minX } action: { probe.leading[row] = $0 }
                        .scrollTransition(configuration) { content, phase in
                            content.offset(x: phase.value * 100)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The same rows, with no transition coming in at the top.
@View
struct BottomOnlyTransitionedRows {
    let probe: RowProbe

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { row in
                    Color.blue.frame(width: 50, height: 50)
                        .onGeometryChange(for: Double.self) { $0.frame(in: .global).minX } action: { probe.leading[row] = $0 }
                        .scrollTransition(topLeading: .identity, bottomTrailing: .interactive(timingCurve: .linear)) { content, phase in
                            content.offset(x: phase.value * 100)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Five cards 100 wide in a 200-wide strip, moved down by their phase.
@View
struct TransitionedStrip {
    let probe: RowProbe

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { card in
                    Color.orange.frame(width: 100, height: 50)
                        .onGeometryChange(for: Double.self) { $0.frame(in: .global).minY } action: { probe.leading[card] = $0 }
                        .scrollTransition(.interactive(timingCurve: .linear)) { content, phase in
                            content.offset(y: phase.value * 100)
                        }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// A row in no scroll view.
@View
struct UnscrolledTransitioned {
    let probe: RowProbe

    var body: some View {
        Color.blue.frame(width: 50, height: 50)
            .onGeometryChange(for: Double.self) { $0.frame(in: .global).minX } action: { probe.leading[0] = $0 }
            .scrollTransition { content, phase in content.offset(x: phase.value * 100) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollTransitions {

        private func scroll(_ harness: Harness, by dy: Double) async {
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -dy)
            await harness.frames(2)
        }

        @Test func interactivelyAViewInViewIsAtIdentityAndOneOutsideAtItsEdgesPhase() {
            let probe = RowProbe()
            _ = Harness(TransitionedRows(probe: probe, configuration: .interactive(timingCurve: .linear)))
            #expect(probe.leading[3] == 0, "row 3 at 150…200 is all in view")
            #expect(probe.leading[4] == 100, "row 4 at 200…250 is just outside the bottom")
        }

        @Test func interactivelyAViewHalfWayToTheThresholdIsHalfWayBetweenThePhases() async {
            let probe = RowProbe()
            let harness = Harness(TransitionedRows(probe: probe, configuration: .interactive(timingCurve: .linear)))

            await scroll(harness, by: 25)
            #expect(probe.leading[4] == 50, "row 4 is 25 of its 50 in at the bottom")
            #expect(probe.leading[0] == -50, "row 0 is 25 of its 50 still in at the top")
        }

        @Test func theTimingCurveShapesTheWayBetween() async {
            let probe = RowProbe()
            let harness = Harness(TransitionedRows(probe: probe, configuration: .interactive(timingCurve: .easeIn)))

            await scroll(harness, by: 25)
            let expected = 100 * (1 - UnitCurve.easeIn.value(at: 0.5))
            #expect(abs((probe.leading[4] ?? 0) - expected) < 1e-9)
        }

        @Test func aCenteredThresholdIsMetOnlyAtTheMiddle() async {
            let probe = RowProbe()
            let harness = Harness(TransitionedRows(
                probe: probe,
                configuration: ScrollTransitionConfiguration.interactive(timingCurve: .linear).threshold(.centered)
            ))
            // Row 2 at 100…150 is past the middle: 100 of the 125 it needs.
            #expect(probe.leading[2] == 20)

            await scroll(harness, by: 25)
            #expect(probe.leading[2] == 0, "75…125: its middle at the scroll view's")
        }

        @Test func theIdentityConfigurationChangesNothing() {
            let probe = RowProbe()
            _ = Harness(TransitionedRows(probe: probe, configuration: .identity))
            #expect(probe.leading[4] == 0)
        }

        @Test func animatedItSwitchesPhaseAtTheThresholdAndAnimatesThere() async {
            let probe = RowProbe()
            let harness = Harness(TransitionedRows(probe: probe, configuration: .animated(.linear(duration: 0.2))))
            #expect(probe.leading[4] == 100, "out of view at first: placed in its phase at once")

            await scroll(harness, by: 25)
            #expect(probe.leading[4] == 100, "half way in is not yet the threshold")

            await scroll(harness, by: 25)
            let moving = probe.leading[4] ?? 0
            #expect(moving < 100)
            #expect(moving > 0, "on its way to identity")

            await harness.settle(0.25)
            await harness.frames(2)
            #expect(probe.leading[4] == 0)
        }

        @Test func eachEdgeCanHaveItsOwnConfiguration() async {
            let probe = RowProbe()
            let harness = Harness(BottomOnlyTransitionedRows(probe: probe))

            await scroll(harness, by: 25)
            #expect(probe.leading[0] == 0, "no transition at the top")
            #expect(probe.leading[4] == 50)
        }

        @Test func aSidewaysScrollViewTransitionsAlongItsAxis() {
            let probe = RowProbe()
            _ = Harness(TransitionedStrip(probe: probe))
            #expect(probe.leading[1] == 0, "card 1 at 100…200 is all in view")
            #expect(probe.leading[2] == 100, "card 2 at 200…300 is just outside the trailing edge")
        }

        @Test func inNoScrollViewTheViewIsAtIdentity() {
            let probe = RowProbe()
            _ = Harness(UnscrolledTransitioned(probe: probe))
            #expect(probe.leading[0] == 0)
        }
    }
}
