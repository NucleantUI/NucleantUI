//
//  ScrollPositionTests.swift
//  NucleantUITests
//
//  `ScrollPosition` as a value, then `.scrollPosition(_:)` and
//  `.scrollPosition(id:)` on a hosted scroll view: a value written to the
//  binding scrolls there; the user scrolling writes back where it is.
//

import Foundation
import Observation
import Testing
@testable import NucleantUI

struct ScrollPositionValueTests {

    @Test func madeForAnIDTypeAloneItIsWhereverTheUserPutsIt() {
        let position = ScrollPosition(idType: Int.self)
        #expect(position.edge == nil)
        #expect(position.point == nil)
        #expect(position.viewID == nil)
        #expect(position.isPositionedByUser == false)
    }

    @Test(arguments: Edge.allCases)
    func madeAtAnEdgeItIsAtThatEdge(edge: Edge) {
        #expect(ScrollPosition(edge: edge).edge == edge)
    }

    @Test func madeAtAPointOrAnXAndYItIsAtThatPoint() {
        #expect(ScrollPosition(point: Point(x: 3, y: 4)).point == Point(x: 3, y: 4))
        #expect(ScrollPosition(x: 1, y: 2).point == Point(x: 1, y: 2))
    }

    @Test func madeAtAnXOrAYAloneItHasNoPoint() {
        #expect(ScrollPosition(x: 5).point == nil)
        #expect(ScrollPosition(y: 5).point == nil)
        #expect(ScrollPosition(x: 5) != ScrollPosition(y: 5))
    }

    @Test func madeAtAViewItHasThatViewsIDOfItsTypeOnly() {
        let position = ScrollPosition(id: 42, anchor: .top)
        #expect(position.viewID == AnyHashable(42))
        #expect(position.viewID(type: Int.self) == 42)
        #expect(position.viewID(type: String.self) == nil)
    }

    enum Move: CaseIterable {
        case edge, point, xAndY, x, y, view

        func apply(to position: inout ScrollPosition) {
            switch self {
            case .edge: position.scrollTo(edge: .bottom)
            case .point: position.scrollTo(point: Point(x: 0, y: 10))
            case .xAndY: position.scrollTo(x: 0, y: 10)
            case .x: position.scrollTo(x: 10)
            case .y: position.scrollTo(y: 10)
            case .view: position.scrollTo(id: 9)
            }
        }
    }

    @Test(arguments: Move.allCases)
    func scrolledSomewhereByTheAppItIsNoLongerWhereTheUserPutIt(move: Move) {
        var position = ScrollPosition(idType: Int.self).scrolledByUser(to: AnyHashable(3))
        move.apply(to: &position)
        #expect(position.isPositionedByUser == false)
        #expect(position != ScrollPosition(idType: Int.self).scrolledByUser(to: AnyHashable(3)))
    }

    @Test func positionedByTheUserItForgetsItsEdgeAndPointButKeepsItsView() {
        var atEdge = ScrollPosition(edge: .bottom)
        atEdge.isPositionedByUser = true
        #expect(atEdge.edge == nil)

        var atPoint = ScrollPosition(point: Point(x: 0, y: 40))
        atPoint.isPositionedByUser = true
        #expect(atPoint.point == nil)

        var atView = ScrollPosition(id: 3)
        atView.isPositionedByUser = true
        #expect(atView.viewID(type: Int.self) == 3)
    }

    @Test func scrolledByTheUserItSaysSoAndNamesTheViewInFront() {
        let position = ScrollPosition(idType: Int.self, edge: .top).scrolledByUser(to: AnyHashable(7))
        #expect(position.isPositionedByUser)
        #expect(position.edge == nil)
        #expect(position.viewID(type: Int.self) == 7)
    }

    @Test func positionsAreEqualWhenTheySayTheSameForTheSameIDType() {
        #expect(ScrollPosition(idType: Int.self, edge: .top) == ScrollPosition(idType: Int.self, edge: .top))
        #expect(ScrollPosition(idType: Int.self, edge: .top) != ScrollPosition(idType: Int.self, edge: .bottom))
        #expect(ScrollPosition(idType: Int.self) != ScrollPosition(idType: String.self))
        #expect(ScrollPosition(id: 1) != ScrollPosition(id: 1, anchor: .top))
    }
}

// MARK: - Hosted

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

/// A header and rows that carry ids of their own — not a `ForEach`'s — in
/// a scroll target layout, its position kept by the view above it.
@View
struct IdentifiedParts {
    let probe: PositionProbe
    @Binding var position: ScrollPosition

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 300).id("header")
                ForEach(0..<20, id: \.self) { row in
                    Color.blue.frame(height: 50).id("row \(row)")
                }
            }
            .scrollTargetLayout()
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .scrollPosition($position, anchor: .top)
    }
}

/// Whether `KeptPartsPosition` shows its scroll view — off and on is a tab
/// left and opened again.
@MainActor
@Observable
final class PartsSwitch {
    var shows = true
}

/// Keeps the position of the `IdentifiedParts` it shows, as a root keeps
/// a tab's.
@View
struct KeptPartsPosition {
    let probe: PositionProbe
    let toggle: PartsSwitch
    @State private var position = ScrollPosition(idType: String.self, edge: .top)

    var body: some View {
        let _ = probe.position = $position
        if toggle.shows {
            IdentifiedParts(probe: probe, position: $position)
        } else {
            Color.gray
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollPositions {

        enum Destination: CaseIterable {
            case bottomEdge, y, nearestView, viewAtItsTop

            func write(to position: inout ScrollPosition) {
                switch self {
                case .bottomEdge: position.scrollTo(edge: .bottom)
                case .y: position.scrollTo(y: 300)
                case .nearestView: position.scrollTo(id: 40)
                case .viewAtItsTop: position.scrollTo(id: 70, anchor: .top)
                }
            }

            /// Where the content's top is then, of 100 rows 50 tall in 200.
            var top: Double {
                switch self {
                case .bottomEdge: -4800
                case .y: -300
                // Row 40 is at 2000…2050: the least move shows it.
                case .nearestView: -1850
                case .viewAtItsTop: -3500
                }
            }
        }

        @Test(arguments: Destination.allCases)
        func writtenToItScrollsWhereItSays(destination: Destination) async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self)))
            let position = try #require(probe.position)

            destination.write(to: &position.wrappedValue)
            await harness.frames(10)
            #expect(probe.top == destination.top)
        }

        @Test func itStartsWhereTheInitialPositionSays() async {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(id: 30, anchor: .top)))
            await harness.frames(10)
            #expect(probe.top == -1500)
        }

        @Test func atTheBottomEdgeItStaysThereAsTheContentGrows() async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self, edge: .bottom)))
            let rows = try #require(probe.rows)
            await harness.frames(3)
            try #require(probe.top == -4800)

            rows.wrappedValue = 120
            await harness.frames(5)
            #expect(probe.top == -5800)
        }

        @Test func scrolledByTheUserItSaysSoAndWhichViewIsInFront() async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedRows(probe: probe, initial: ScrollPosition(idType: Int.self, edge: .top)))
            harness.host.scrollsOnDrag = true
            let binding = try #require(probe.position)
            await harness.frames(2)

            harness.drag(from: Point(x: 100, y: 190), by: Point(x: 0, y: -260))
            await harness.frames(3)
            try #require(probe.top == -260)

            let position = binding.wrappedValue
            #expect(position.isPositionedByUser)
            #expect(position.edge == nil)
            #expect(position.viewID(type: Int.self) == 5, "260 down, row 5 (250…300) is the first in view")

            await harness.frames(3)
            #expect(probe.top == -260, "handed back, it does not move")
        }

        @Test func anIDBindingFollowsTheUser() async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedByID(probe: probe))
            let scrolledID = try #require(probe.scrolledID)
            harness.host.pointerMoved(to: center)

            harness.host.scroll(dx: 0, dy: -520)
            harness.host.update()
            await harness.frames(3)
            #expect(scrolledID.wrappedValue == 10, "520 down, row 10 (500…550) is the first in view")
        }

        @Test func anIDWrittenToTheBindingIsScrolledToAndKept() async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedByID(probe: probe))
            let scrolledID = try #require(probe.scrolledID)

            scrolledID.wrappedValue = 70
            await harness.frames(3)
            #expect(probe.top == -3350, "row 70 is at 3500…3550: the least move shows it")
            #expect(scrolledID.wrappedValue == 70)
        }

        @Test func anIDWrittenWhileTheUsersScrollIsReportedIsNotReplacedByTheViewInFront() async throws {
            let probe = PositionProbe()
            let harness = Harness(PositionedByID(probe: probe))
            let scrolledID = try #require(probe.scrolledID)
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -520)
            await harness.frames(2)
            try #require(scrolledID.wrappedValue == 10)

            // The wheel's scroll is still going on (it is over once the
            // wheel has been still a moment) when the app writes.
            scrolledID.wrappedValue = 70
            await harness.frames(3)
            #expect(probe.top == -3350)
            #expect(scrolledID.wrappedValue == 70, "row 67 is the first in view there, but 70 was asked for")
        }

        @Test func theViewInFrontIsFoundByAnIDOfItsOwn() async throws {
            let probe = PositionProbe()
            let toggle = PartsSwitch()
            let harness = Harness(KeptPartsPosition(probe: probe, toggle: toggle))
            harness.host.scrollsOnDrag = true
            let binding = try #require(probe.position)
            await harness.frames(2)

            harness.drag(from: Point(x: 100, y: 190), by: Point(x: 0, y: -160))
            await harness.frames(3)
            try #require(probe.top == -160)
            #expect(binding.wrappedValue.viewID(type: String.self) == "header", "the header is under the top")

            harness.drag(from: Point(x: 100, y: 190), by: Point(x: 0, y: -200))
            await harness.frames(3)
            try #require(probe.top == -360)
            #expect(binding.wrappedValue.viewID(type: String.self) == "row 1", "row 1 (350…400) is under the top")
        }

        @Test func builtAgainItGoesBackToTheViewThePositionNames() async throws {
            let probe = PositionProbe()
            let toggle = PartsSwitch()
            let harness = Harness(KeptPartsPosition(probe: probe, toggle: toggle))
            harness.host.scrollsOnDrag = true
            await harness.frames(2)
            harness.drag(from: Point(x: 100, y: 190), by: Point(x: 0, y: -360))
            await harness.frames(3)
            try #require(probe.top == -360)

            toggle.shows = false
            await harness.frames(2)
            toggle.shows = true
            await harness.frames(3)
            #expect(probe.top == -350, "row 1 at the top")
        }
    }
}
