//
//  ScrollContentOffsetAdjustmentBehaviorTests.swift
//  NucleantUITests
//
//  `Transaction.scrollContentOffsetAdjustmentBehavior`: a frame's changes
//  folded together, a scroller at rest that keeps or leaves its place as
//  the content grows, and a hosted scroll view anchored to its bottom
//  under a change that asks it to stay.
//

import Foundation
import Observation
import Testing
@testable import NucleantUI

@MainActor
struct ScrollContentOffsetAdjustmentTransactionTests {

    @Test func aTransactionAdjustsUnlessToldNotTo() {
        #expect(Transaction().scrollContentOffsetAdjustmentBehavior.role == .automatic)
    }

    @Test(arguments: [
        (ScrollContentOffsetAdjustmentBehavior.Role.automatic, ScrollContentOffsetAdjustmentBehavior.Role.automatic, ScrollContentOffsetAdjustmentBehavior.Role.automatic),
        (.automatic, .disabled, .disabled),
        (.disabled, .automatic, .disabled),
    ])
    func aFrameServingAChangeThatAskedTheOffsetToStayLeavesIt(
        first: ScrollContentOffsetAdjustmentBehavior.Role,
        later: ScrollContentOffsetAdjustmentBehavior.Role,
        merged: ScrollContentOffsetAdjustmentBehavior.Role
    ) {
        var transaction = Transaction()
        transaction.scrollContentOffsetAdjustmentBehavior = ScrollContentOffsetAdjustmentBehavior(role: first)
        var next = Transaction()
        next.scrollContentOffsetAdjustmentBehavior = ScrollContentOffsetAdjustmentBehavior(role: later)
        transaction.merge(next)
        #expect(transaction.scrollContentOffsetAdjustmentBehavior.role == merged)
    }
}

@MainActor
struct ScrollerOffsetAdjustmentTests {

    private static let viewport = Size(width: 200, height: 200)

    /// A scroller over content 1000 tall, kept to its bottom as sizes
    /// change, scrolled to `offset`.
    private func scroller(at offset: Double) -> Scroller {
        let scroller = Scroller()
        scroller.sizeChangeAnchor = .bottom
        _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1000), at: 0)
        scroller.scroll(to: Point(x: 0, y: offset), animation: nil, at: 0)
        return scroller
    }

    @Test(arguments: [(true, 600.0), (false, 500)])
    func atRestItKeepsItsPlaceFromTheAnchorAsTheContentGrowsUnlessToldToStay(adjusts: Bool, offset: Double) {
        let scroller = scroller(at: 500)
        scroller.adjustsContentOffset = adjusts
        let placed = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 1100), at: 0.1)
        #expect(placed.y == offset)
    }

    @Test func toldToStayItStillRestsInsideTheContent() {
        let scroller = scroller(at: 800)
        scroller.adjustsContentOffset = false
        let placed = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: 500), at: 0.1)
        #expect(placed.y == 300)
    }

    @Test func toldToStayItIsNoLongerPinnedToTheEdgeAPositionPutItAt() throws {
        let scroller = Scroller()
        let node = ContentNode(content: GroupContent())
        var time = 0.0
        /// One placement of content `height` tall, as a scroll view does.
        func pass(height: Double) {
            time += 1.0 / 60
            _ = scroller.place(viewport: Self.viewport, contentSize: Size(width: 200, height: height), at: time)
            _ = scroller.endPlacingContent(node: node, at: time)
        }
        pass(height: 1000)
        scroller.pin(to: .bottom, animation: nil)
        for _ in 0..<10 { pass(height: 1000) }
        try #require(!scroller.hasPendingRequest)
        #expect(scroller.offset.y == 800)

        scroller.adjustsContentOffset = false
        pass(height: 1100)
        #expect(scroller.offset.y == 800, "where it was")

        scroller.adjustsContentOffset = true
        pass(height: 1200)
        #expect(scroller.offset.y == 800, "and not taken back to the bottom by the next change")
    }
}

// MARK: - Hosted

/// How many messages there are.
@MainActor
@Observable
final class MessageLog {
    var count = 20
}

/// Messages 50 tall in a scroll view anchored to its bottom.
@View
struct AnchoredMessages {
    let probe: ScrollProbe
    let log: MessageLog

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<log.count, id: \.self) { _ in
                    Color.blue.frame(height: 50)
                }
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
        .defaultScrollAnchor(.bottom)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollContentOffsetAdjustment {

        @Test(arguments: [(false, -900.0), (true, -800)])
        func aChangeThatAsksTheOffsetToStayLeavesItWhereItWas(disabled: Bool, top: Double) async throws {
            let probe = ScrollProbe()
            let log = MessageLog()
            let harness = Harness(AnchoredMessages(probe: probe, log: log))
            try #require(probe.top == -800, "starts at the bottom")

            var transaction = Transaction()
            if disabled { transaction.scrollContentOffsetAdjustmentBehavior = .disabled }
            withTransaction(transaction) { log.count += 2 }
            await harness.frames(2)
            #expect(probe.top == top)
        }
    }
}
