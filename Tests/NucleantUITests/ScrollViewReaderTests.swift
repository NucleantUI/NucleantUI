//
//  ScrollViewReaderTests.swift
//  NucleantUITests
//
//  Scrolling to a view by its id through a `ScrollViewReader`'s proxy: in a
//  stack, by `.id`, along an animation, stopped by a finger, and in a lazy
//  stack or grid far outside what it has built.
//

import Foundation
import Testing
@testable import NucleantUI

/// Fifty rows 40 tall and a footer `.id("footer")`, in 200.
@View
struct ReaderRows {
    let probe: ReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            let _ = probe.proxy = proxy
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<50) { _ in
                        Color.blue.frame(height: 40)
                    }
                    Color.red.frame(height: 40).id("footer")
                }
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
            }
        }
    }
}

@View
struct ReaderLazyRows {
    let probe: ReaderProbe
    /// Rows alternate between these heights.
    let heights: (Double, Double)

    var body: some View {
        ScrollViewReader { proxy in
            let _ = probe.proxy = proxy
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<1000) { row in
                        Color.blue.frame(height: row % 2 == 0 ? heights.0 : heights.1)
                            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { top in
                                if row == probe.watched { probe.watchedTop = top }
                            }
                    }
                }
                .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { probe.top = $0 }
            }
        }
    }
}

@View
struct ReaderLazyGrid {
    let probe: ReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            let _ = probe.proxy = proxy
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<900) { cell in
                        Color.green.frame(height: 50)
                            .onGeometryChange(for: Double.self) { $0.frame(in: .scrollView).minY } action: { top in
                                if cell == probe.watched { probe.watchedTop = top }
                            }
                    }
                }
            }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollViewReaders {

        @Test(arguments: [
            // Row 30 is at 1200…1240: the least move shows its bottom at
            // the viewport's.
            (30, UnitPoint?.none, -1040.0),
            (10, .top, -400),
            (5, .center, -120),
            (49, .bottom, -1800),
        ])
        func toARowOfAForEachTheLeastMoveOrItsAnchor(row: Int, anchor: UnitPoint?, top: Double) async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo(row, anchor: anchor)
            await harness.frames(2)
            #expect(probe.top == top)
        }

        @Test func aRowAlreadyInViewIsNotMovedTo() async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)
            proxy.scrollTo(30)
            await harness.frames(2)
            try #require(probe.top == -1040)

            proxy.scrollTo(29)
            await harness.frames(2)
            #expect(probe.top == -1040)
        }

        @Test func toAViewByItsID() async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo("footer", anchor: .bottom)
            await harness.frames(2)
            #expect(probe.top == -1840)
        }

        @Test(arguments: ["nowhere", "Footer"])
        func toAnIDNothingHasNothingMoves(id: String) async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo(id)
            await harness.frames(2)
            #expect(probe.top == 0)
        }

        @Test func toAnIDOfAnotherTypeNothingMoves() async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)

            // The rows are identified by `Int`; 30 as a `UInt` is no row's.
            proxy.scrollTo(UInt(30))
            await harness.frames(2)
            #expect(probe.top == 0)
        }

        @Test func insideWithAnimationItGoesAlongTheAnimation() async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            let proxy = try #require(probe.proxy)

            withAnimation(.linear(duration: 0.3)) {
                proxy.scrollTo(30, anchor: .top)
            }
            await harness.frames(6)
            #expect(probe.top < 0, "on its way")
            #expect(probe.top > -1200, "not there yet")
            await harness.settle(0.35)
            await harness.frames(2)
            #expect(probe.top == -1200)
        }

        @Test func aFingerStopsAScrollTheAppAskedFor() async throws {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            harness.host.scrollsOnDrag = true
            let proxy = try #require(probe.proxy)

            withAnimation(.linear(duration: 1)) {
                proxy.scrollTo(30, anchor: .top)
            }
            await harness.frames(10)
            harness.host.pointerDown(at: center)
            harness.host.update()
            let caught = probe.top
            try #require(caught < 0, "caught on its way")

            await harness.frames(10)
            #expect(probe.top == caught)
            harness.host.pointerUp(at: center)
        }

        @Test func farOutsideALazyStacksWindowItArrivesAtTheRow() async throws {
            let probe = ReaderProbe()
            probe.watched = 800
            let harness = Harness(ReaderLazyRows(probe: probe, heights: (40, 40)))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo(800, anchor: .top)
            await harness.frames(20)
            #expect(probe.top == -32_000)
            #expect(probe.watchedTop == 0, "the row was built, and is at the top")
        }

        @Test func rowsOfUnequalHeightsAreFoundAsTheyAreBuilt() async throws {
            let probe = ReaderProbe()
            probe.watched = 701
            let harness = Harness(ReaderLazyRows(probe: probe, heights: (30, 70)))
            let proxy = try #require(probe.proxy)

            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(701, anchor: .top)
            }
            await harness.settle(0.3)
            await harness.frames(30)
            let top = try #require(probe.watchedTop, "the row was built")
            #expect(abs(top) < 0.5, "the gap's estimate was corrected as rows came in")
        }

        @Test func farDownALazyGridItArrivesAtTheCellsLine() async throws {
            let probe = ReaderProbe()
            probe.watched = 751
            let harness = Harness(ReaderLazyGrid(probe: probe))
            let proxy = try #require(probe.proxy)

            proxy.scrollTo(751, anchor: .top)
            await harness.frames(20)
            #expect(probe.watchedTop == 0)
        }
    }
}
