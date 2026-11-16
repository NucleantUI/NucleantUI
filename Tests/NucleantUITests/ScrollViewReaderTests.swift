//
//  ScrollViewReaderTests.swift
//  NucleantUITests
//
//  `.id(_:)` and scrolling to a view by its id: in a stack, by `.id`, along
//  an animation, and in a lazy stack far outside what it has built.
//

import Foundation
import Testing
@testable import NucleantUI

/// What a test drives a reader with, and what its views report.
@MainActor
final class ReaderProbe {
    var proxy: ScrollViewProxy?
    var top = 0.0
    /// Where row `watched` is in the scroll view, once placed.
    var watched = -1
    var watchedTop: Double?
}

@View
struct ReaderRows {
    let probe: ReaderProbe

    var body: some View {
        ScrollViewReader { proxy in
            let _ = probe.proxy = proxy
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<50) { row in
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

/// A counter whose identity is `version`.
@View
struct VersionedCounter {
    let version: Int
    let log: Log

    var body: some View {
        IdentifiedCounter(log: log).id(version)
    }
}

@View
struct IdentifiedCounter {
    let log: Log
    @State private var count = 0

    var body: some View {
        Button("count") {
            count += 1
            log("count \(count)")
        }
        .frame(width: 200, height: 200)
    }
}

@MainActor
final class VersionBox {
    var version = 0
}

@View
struct VersionedCounterHost {
    let box: VersionBox
    let log: Log
    @State private var version = 0

    var body: some View {
        let _ = box.version = version
        VStack(spacing: 0) {
            VersionedCounter(version: version, log: log)
            Button("next") { version += 1 }
                .frame(width: 200, height: 40)
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct ScrollingToViews {

        private func frames(_ count: Int, _ harness: Harness) async {
            for _ in 0..<count { await harness.settle(1.0 / 60) }
        }

        @Test func aNewIdIsANewViewWithItsOwnState() async {
            let log = Log()
            let box = VersionBox()
            let harness = Harness(VersionedCounterHost(box: box, log: log), size: Size(width: 200, height: 240))
            await harness.tap(Point(x: 100, y: 100))
            await harness.tap(Point(x: 100, y: 100))
            #expect(log.take() == ["count 1", "count 2"])

            await harness.tap(Point(x: 100, y: 220))
            await frames(30, harness)
            #expect(box.version == 1)
            await harness.tap(Point(x: 100, y: 100))
            #expect(log.take() == ["count 1"])
        }

        @Test func toARowOfAForEachTheLeastMoveOrToAnAnchor() async {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))

            // Row 30 is at 1200…1240: the least move shows its bottom at the
            // viewport's.
            probe.proxy?.scrollTo(30)
            await frames(2, harness)
            #expect(probe.top == -1040)

            // Already in view: nothing moves.
            probe.proxy?.scrollTo(29)
            await frames(2, harness)
            #expect(probe.top == -1040)

            probe.proxy?.scrollTo(10, anchor: .top)
            await frames(2, harness)
            #expect(probe.top == -400)

            probe.proxy?.scrollTo(5, anchor: .center)
            await frames(2, harness)
            #expect(probe.top == -120)

            // By `.id`: the footer's bottom at the viewport's bottom.
            probe.proxy?.scrollTo("footer", anchor: .bottom)
            await frames(2, harness)
            #expect(probe.top == -1840)

            // An id nothing has: nothing moves.
            probe.proxy?.scrollTo("nowhere")
            await frames(2, harness)
            #expect(probe.top == -1840)
        }

        @Test func insideWithAnimationItGoesAlongTheAnimation() async {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))

            withAnimation(.linear(duration: 0.3)) {
                probe.proxy?.scrollTo(30, anchor: .top)
            }
            await frames(6, harness)
            #expect(probe.top < 0)
            #expect(probe.top > -1200)
            await harness.settle(0.35)
            await frames(2, harness)
            #expect(probe.top == -1200)
        }

        @Test func aFingerStopsAScrollTheAppAskedFor() async {
            let probe = ReaderProbe()
            let harness = Harness(ReaderRows(probe: probe))
            harness.host.scrollsOnDrag = true

            withAnimation(.linear(duration: 1)) {
                probe.proxy?.scrollTo(30, anchor: .top)
            }
            await frames(10, harness)
            harness.host.pointerDown(at: center)
            harness.host.update()
            let caught = probe.top
            #expect(caught < 0)
            await frames(10, harness)
            #expect(probe.top == caught)
            harness.host.pointerUp(at: center)
        }

        @Test func farOutsideALazyStacksWindowItArrivesAtTheRow() async {
            let probe = ReaderProbe()
            probe.watched = 800
            let harness = Harness(ReaderLazyRows(probe: probe, heights: (40, 40)))

            probe.proxy?.scrollTo(800, anchor: .top)
            await frames(20, harness)
            #expect(probe.top == -32_000)
            #expect(probe.watchedTop == 0)
        }

        @Test func farDownALazyGridItArrivesAtTheCellsLine() async {
            let probe = ReaderProbe()
            probe.watched = 751
            let harness = Harness(ReaderLazyGrid(probe: probe))

            probe.proxy?.scrollTo(751, anchor: .top)
            await frames(20, harness)
            #expect(probe.watchedTop == 0)
        }

        @Test func rowsOfUnequalHeightsAreFoundAsTheyAreBuilt() async {
            let probe = ReaderProbe()
            probe.watched = 701
            let harness = Harness(ReaderLazyRows(probe: probe, heights: (30, 70)))

            withAnimation(.easeInOut(duration: 0.2)) {
                probe.proxy?.scrollTo(701, anchor: .top)
            }
            await harness.settle(0.3)
            await frames(30, harness)
            #expect(probe.watchedTop.map { abs($0) < 0.5 } == true)
        }
    }
}
