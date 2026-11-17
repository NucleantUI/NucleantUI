//
//  DefaultScrollAnchorTests.swift
//  NucleantUITests
//
//  `.defaultScrollAnchor`: which anchor each role gets, then a hosted
//  scroll view starting, keeping its place and aligning its content by it.
//

import Foundation
import Testing
@testable import NucleantUI

@MainActor
struct DefaultScrollAnchorModifierTests {

    @Test(arguments: [ScrollAnchorRole.Kind.initialOffset, .sizeChanges, .alignment])
    func oneAnchorForEveryRole(role: ScrollAnchorRole.Kind) {
        var environment = EnvironmentValues()
        DefaultScrollAnchorModifier(anchor: .bottom).modifyEnvironment(&environment)
        #expect(environment.scrollAnchors.anchor(for: role) == .bottom)
    }

    @Test(arguments: [ScrollAnchorRole.initialOffset, .sizeChanges, .alignment])
    func anAnchorForOneRoleGoesBeforeTheOneForEvery(role: ScrollAnchorRole) {
        var environment = EnvironmentValues()
        DefaultScrollAnchorModifier(anchor: .bottom).modifyEnvironment(&environment)
        DefaultScrollAnchorRoleModifier(anchor: .topLeading, role: role).modifyEnvironment(&environment)
        let anchors = environment.scrollAnchors
        for other in [ScrollAnchorRole.initialOffset, .sizeChanges, .alignment] {
            #expect(anchors.anchor(for: other.kind) == (other == role ? .topLeading : .bottom))
        }
    }

    @Test func noAnchorSetForOneRoleIsNoneThoughEveryRoleHasOne() {
        var environment = EnvironmentValues()
        DefaultScrollAnchorModifier(anchor: .bottom).modifyEnvironment(&environment)
        DefaultScrollAnchorRoleModifier(anchor: nil, role: .alignment).modifyEnvironment(&environment)
        #expect(environment.scrollAnchors.anchor(for: .alignment) == nil)
        #expect(environment.scrollAnchors.anchor(for: .initialOffset) == .bottom)
    }

    @Test func nothingSetIsNoAnchor() {
        let anchors = EnvironmentValues().scrollAnchors
        #expect(anchors.anchor(for: .initialOffset) == nil)
        #expect(anchors.anchor(for: .sizeChanges) == nil)
        #expect(anchors.anchor(for: .alignment) == nil)
    }
}

// MARK: - Hosted

/// `rows` rows 50 tall in a 200×200 scroll view, anchored at `anchor`;
/// alignment at `alignment`, when given.
@View
struct AnchoredRows {
    let probe: PositionProbe
    let anchor: UnitPoint?
    let alignment: UnitPoint??
    @State private var rows: Int

    init(probe: PositionProbe, rows: Int, anchor: UnitPoint?, alignment: UnitPoint?? = .none) {
        self.probe = probe
        self.anchor = anchor
        self.alignment = alignment
        self.rows = rows
    }

    var body: some View {
        let _ = probe.rows = $rows
        if let alignment {
            scroll
                .defaultScrollAnchor(anchor)
                .defaultScrollAnchor(alignment, for: .alignment)
        } else {
            scroll.defaultScrollAnchor(anchor)
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { _ in
                    Color.blue.frame(height: 50)
                }
            }
            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
        }
    }
}

/// Content twice the viewport each way, scrolled both ways from the center.
@View
struct CenteredPlane {
    let probe: ScrollProbe

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Color.green.frame(width: 400, height: 400)
                .onGeometryChange(for: Rect.self) { $0.frame(in: .scrollView) } action: { frame in
                    probe.leading = frame.minX
                    probe.top = frame.minY
                }
        }
        .defaultScrollAnchor(.center)
    }
}

extension HostedViews {
    @MainActor
    @Suite struct DefaultScrollAnchors {

        @Test func atTheBottomAnchorItStartsAtTheBottom() {
            let probe = PositionProbe()
            _ = Harness(AnchoredRows(probe: probe, rows: 20, anchor: .bottom))
            #expect(probe.top == -800)
        }

        @Test func atTheCenterAnchorItStartsInTheMiddleBothWays() {
            let probe = ScrollProbe()
            _ = Harness(CenteredPlane(probe: probe))
            #expect(probe.leading == -100)
            #expect(probe.top == -100)
        }

        @Test func atTheBottomAsRowsAreAddedItStaysAtTheBottom() async throws {
            let probe = PositionProbe()
            let harness = Harness(AnchoredRows(probe: probe, rows: 20, anchor: .bottom))
            let rows = try #require(probe.rows)

            rows.wrappedValue = 24
            await harness.frames(2)
            #expect(probe.top == -1000)
        }

        @Test func withoutAnAnchorAddedRowsLeaveItWhereItIs() async throws {
            let probe = PositionProbe()
            let harness = Harness(AnchoredRows(probe: probe, rows: 20, anchor: nil))
            let rows = try #require(probe.rows)
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -300)
            await harness.frames(2)
            try #require(probe.top == -300)

            rows.wrappedValue = 24
            await harness.frames(2)
            #expect(probe.top == -300)
        }

        @Test func contentShorterThanTheScrollViewSitsAtTheAlignmentAnchor() {
            let probe = PositionProbe()
            _ = Harness(AnchoredRows(probe: probe, rows: 2, anchor: .bottom))
            #expect(probe.top == 100, "100 tall in 200, at the bottom")
        }

        @Test func anAlignmentAnchorOfItsOwnGoesBeforeTheAnchorForEveryRole() {
            let probe = PositionProbe()
            _ = Harness(AnchoredRows(probe: probe, rows: 2, anchor: .bottom, alignment: .topLeading))
            #expect(probe.top == 0, "short content at the top, as the documentation's example has it")

            let tall = PositionProbe()
            _ = Harness(AnchoredRows(probe: tall, rows: 20, anchor: .bottom, alignment: .topLeading))
            #expect(tall.top == -800, "and long content still starts at the bottom")
        }
    }
}
