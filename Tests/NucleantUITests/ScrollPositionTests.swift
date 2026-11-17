//
//  ScrollPositionTests.swift
//  NucleantUITests
//
//  `.scrollPosition(_:)` and `.scrollPosition(id:)`: a value written to the
//  binding scrolls there; the user scrolling writes back where it is.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
final class PositionProbe {
    var position: Binding<ScrollPosition>?
    var scrolledID: Binding<Int?>?
    var rows: Binding<Int>?
    var top = 0.0
}

@View
struct PositionedRows {
    let probe: PositionProbe
    let initial: ScrollPosition
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var rows = 100

    init(probe: PositionProbe, initial: ScrollPosition) {
        self.probe = probe
        self.initial = initial
        self.position = initial
    }

    var body: some View {
        let _ = probe.position = $position
        let _ = probe.rows = $rows
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { _ in
                    Color.blue.frame(height: 50)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollPosition($position)
    }
}

@View
struct PositionedByID {
    let probe: PositionProbe
    @State private var scrolledID: Int?

    var body: some View {
        let _ = probe.scrolledID = $scrolledID
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<100) { _ in
                    Color.orange.frame(height: 50)
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollPosition(id: $scrolledID)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollPositions {

        private func frames(_ count: Int, _ harness: Harness) async {
            for _ in 0..<count { await harness.settle(1.0 / 60) }
        }

        @Test func writtenToItScrollsToTheEdgeThePointOrTheView() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self)))
            #expect(probe.top == 0)

            probe.position?.wrappedValue.scrollTo(edge: .bottom)
            await frames(3, harness)
            #expect(probe.top == -4800)

            probe.position?.wrappedValue.scrollTo(y: 300)
            await frames(3, harness)
            #expect(probe.top == -300)

            // Row 40 is at 2000…2050: the least move shows it.
            probe.position?.wrappedValue.scrollTo(id: 40)
            await frames(10, harness)
            #expect(probe.top == -1850)

            probe.position?.wrappedValue.scrollTo(id: 70, anchor: .top)
            await frames(10, harness)
            #expect(probe.top == -3500)
            #expect(probe.position?.wrappedValue.viewID(type: Int.self) == 70)
        }

        @Test func itStartsWhereTheInitialPositionSays() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(id: 30, anchor: .top)))
            await frames(10, harness)
            #expect(probe.top == -1500)
        }

        @Test func atTheBottomEdgeItStaysThereAsTheContentGrows() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self, edge: .bottom)))
            await frames(3, harness)
            #expect(probe.top == -4800)

            probe.rows?.wrappedValue = 120
            await frames(5, harness)
            #expect(probe.top == -5800)
        }

        @Test func scrolledByTheUserItSaysSoAndWhichViewIsInFront() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self, edge: .top)))
            harness.host.scrollsOnDrag = true
            await frames(2, harness)

            harness.host.pointerDown(at: Point(x: 100, y: 190))
            harness.host.pointerMoved(to: Point(x: 100, y: 60))
            harness.host.pointerMoved(to: Point(x: 100, y: -70))
            harness.host.pointerUp(at: Point(x: 100, y: -70))
            await frames(3, harness)
            #expect(probe.top == -260)

            let position = probe.position?.wrappedValue
            #expect(position?.isPositionedByUser == true)
            #expect(position?.edge == nil)
            // 260 down, row 5 (250…300) is the first in view.
            #expect(position?.viewID(type: Int.self) == 5)

            // Handed back, it does not move.
            await frames(3, harness)
            #expect(probe.top == -260)
        }

        @Test func anIDBindingFollowsTheUserAndScrollsWhenWritten() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedByID(probe: probe))
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -520)
            harness.host.update()
            await frames(3, harness)
            #expect(probe.scrolledID?.wrappedValue == 10)

            probe.scrolledID?.wrappedValue = 70
            await frames(3, harness)
            // Row 70 is at 3500…3550: the least move shows it.
            #expect(probe.top == -3350)
            #expect(probe.scrolledID?.wrappedValue == 70)
        }
    }
}
