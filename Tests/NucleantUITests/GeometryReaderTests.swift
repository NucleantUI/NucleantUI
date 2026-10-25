//
//  GeometryReaderTests.swift
//  NucleantUITests
//
//  `GeometryReader`, `GeometryProxy`, coordinate spaces and
//  `.onGeometryChange`, hosted: content built for the size it is placed at
//  in the very first frame, and built again when an answer it read
//  changes — and only then; state inside kept across those builds and let
//  go of when its view goes; frames answered in the window, the view, a
//  named ancestor and a scroll view; actions run on the first placement
//  and on every change after it.
//

import Observation
import Testing
@testable import NucleantUI

/// `x,y w×h`, in whole points.
private func describe(_ rect: Rect) -> String {
    "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
}

/// A reader filling the window, logging the size each build of its content
/// was for, with a 20-point square that logs taps.
@View
struct SizeReporter {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            let _ = log("built \(Int(proxy.size.width))×\(Int(proxy.size.height))")
            Color.red
                .frame(width: 20, height: 20)
                .onTapGesture { log("tap") }
        }
    }
}

/// Taps counted in `@State`.
@View
struct TapCounter {
    let log: Log
    @State private var count = 0

    var body: some View {
        Color.red
            .frame(width: 20, height: 20)
            .onTapGesture {
                count += 1
                log("count \(count)")
            }
    }
}

/// A counter only while the reader is wider than 150 points.
@View
struct WideOnlyCounter {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 150 {
                TapCounter(log: log)
            }
        }
    }
}

/// A row whose reader reads only its size.
@View
struct SizeRow {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            let _ = log("size \(Int(proxy.size.width))")
            Color.blue
        }
    }
}

/// A row whose reader reads where it is in the scroll view.
@View
struct TopRow {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            let _ = log("top \(Int(proxy.frame(in: .scrollView).minY)) of \(Int(proxy.bounds(of: .scrollView)?.height ?? -1))")
            Color.green
        }
    }
}

/// Both rows 300 points down a scroll view.
@View
struct ScrolledReaders {
    let log: Log

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 300)
                SizeRow(log: log).frame(height: 40)
                TopRow(log: log).frame(height: 40)
            }
        }
    }
}

/// A 100×50 reader, 40 points down a stack named "stack" that is itself 30
/// points down the window, centred across its 200 points.
@View
struct NamedSpaceReader {
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 40)
            GeometryReader { proxy in
                let _ = log("stack \(describe(proxy.frame(in: .named("stack"))))")
                let _ = log("global \(describe(proxy.frame(in: .global)))")
                let _ = log("local \(describe(proxy.frame(in: .local)))")
                let _ = log("missing \(describe(proxy.frame(in: .named("missing"))))")
                let _ = log("bounds \(proxy.bounds(of: .named("stack")).map(describe) ?? "nil")")
                let _ = log("no bounds \(proxy.bounds(of: .named("missing")).map(describe) ?? "nil")")
                Color.blue
            }
            .frame(width: 100, height: 50)
        }
        .coordinateSpace(.named("stack"))
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A 50-point reader in the middle of the window, scaled up twice about
/// its centre.
@View
struct ScaledReader {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            let _ = log("global \(describe(proxy.frame(in: .global)))")
            let _ = log("size \(Int(proxy.size.width))×\(Int(proxy.size.height))")
            Color.blue
        }
        .frame(width: 50, height: 50)
        .scaleEffect(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Content that reads a model as well as the size.
@View
struct ObservingReader {
    let knobs: Knobs
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            let _ = log("\(knobs.value) at \(Int(proxy.size.width))")
            Color.blue
        }
    }
}

/// A proxy kept by a tap action, read only when the tap comes.
@View
struct KeptProxy {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            Color.red
                .frame(width: 20, height: 20)
                .onTapGesture { log("tapped at width \(Int(proxy.size.width))") }
        }
    }
}

/// Both `.onGeometryChange` overloads on one view, whose body also reads
/// a model.
@View
struct WidthWatcher {
    let knobs: Knobs
    let log: Log

    var body: some View {
        let unrelated = knobs.unrelated
        Color.orange
            .onGeometryChange(for: Double.self) { proxy in
                proxy.size.width
            } action: { width in
                log("width \(Int(width)), unrelated \(unrelated)")
            }
            .onGeometryChange(for: Double.self) { proxy in
                proxy.size.width
            } action: { old, new in
                log("\(Int(old)) → \(Int(new))")
            }
    }
}

/// Where a reader is across the window; -1 with none there.
struct ReaderLeadingKey: PreferenceKey {
    static let defaultValue = -1.0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

/// A reader at the window's top-leading corner, while the model says so,
/// arriving from 100 points to the right, and reporting where it is
/// across the window as a preference.
@View
struct ArrivingReader {
    let knobs: Knobs
    let log: Log

    var body: some View {
        ZStack {
            if knobs.isShown {
                GeometryReader { proxy in
                    Color.blue.preference(key: ReaderLeadingKey.self, value: proxy.frame(in: .global).minX)
                }
                .frame(width: 50, height: 50)
                .transition(.offset(x: 100))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(ReaderLeadingKey.self) { log("at \(Int($0))") }
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct GeometryReaderTests {

        @Test func theFirstFrameIsBuiltForTheSizeTheReaderIsGiven() {
            let log = Log()
            _ = Harness(SizeReporter(log: log))
            #expect(log.take() == ["built 200×200"])
        }

        @Test func contentSitsAtTheTopLeadingCorner() async {
            let log = Log()
            let harness = Harness(SizeReporter(log: log))
            _ = log.take()
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["tap"])
            await harness.tap(center)
            #expect(log.take() == [])
        }

        @Test func aResizeBuildsTheContentForTheNewSize() {
            let log = Log()
            let harness = Harness(SizeReporter(log: log))
            _ = log.take()
            harness.host.setSize(Size(width: 300, height: 120))
            harness.host.update()
            #expect(log.take().last == "built 300×120")
        }

        @Test func stateInsideIsKeptAcrossBuildsAndLetGoOfWhenItsViewGoes() async {
            let log = Log()
            let harness = Harness(WideOnlyCounter(log: log))
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["count 1"])

            // Still wide: built again for 180, the counter kept.
            harness.host.setSize(Size(width: 180, height: 200))
            harness.host.update()
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["count 2"])

            // Narrow: the counter goes, and its count with it.
            harness.host.setSize(Size(width: 100, height: 200))
            harness.host.update()
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == [])

            harness.host.setSize(Size(width: 200, height: 200))
            harness.host.update()
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["count 1"])
        }

        @Test func onlyContentThatReadsWhereItIsIsBuiltAgainWhenItMoves() async {
            let log = Log()
            let harness = Harness(ScrolledReaders(log: log))
            #expect(log.take() == ["size 200", "top 340 of 200"])

            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -100)
            harness.host.update()
            #expect(log.take() == ["top 240 of 200"])
        }

        @Test func framesInTheWindowTheViewAndANamedAncestor() {
            let log = Log()
            _ = Harness(NamedSpaceReader(log: log))
            #expect(log.take() == [
                "stack 50,40 100×50",
                "global 50,70 100×50",
                "local 0,0 100×50",
                // No ancestor by that name: measured in the window.
                "missing 50,70 100×50",
                "bounds -50,-40 200×90",
                "no bounds nil",
            ])
        }

        @Test func aGlobalFrameIsTheBoxOnScreenAndTheSizeIsTheLaidOutOne() {
            let log = Log()
            _ = Harness(ScaledReader(log: log))
            #expect(log.take() == ["global 50,50 100×100", "size 50×50"])
        }

        @Test func modelReadsInTheContentAreTrackedThroughEveryBuild() {
            let log = Log()
            let knobs = Knobs()
            let harness = Harness(ObservingReader(knobs: knobs, log: log))
            #expect(log.take() == ["0 at 200"])

            knobs.value = 1
            harness.host.update()
            #expect(log.take() == ["1 at 200"])

            // Built during placement this time, for the new size.
            harness.host.setSize(Size(width: 150, height: 200))
            harness.host.update()
            #expect(log.take().last == "1 at 150")

            knobs.value = 2
            harness.host.update()
            #expect(log.take() == ["2 at 150"])
        }

        @Test func aProxyKeptPastTheBuildAnswersForWhereTheReaderIsNow() async {
            let log = Log()
            let harness = Harness(KeptProxy(log: log))
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["tapped at width 200"])

            harness.host.setSize(Size(width: 150, height: 200))
            harness.host.update()
            await harness.tap(Point(x: 10, y: 10))
            #expect(log.take() == ["tapped at width 150"])
        }

        @Test func onGeometryChangeRunsWhenPlacedAndWhenTheValueChanges() {
            let log = Log()
            let knobs = Knobs()
            let harness = Harness(WidthWatcher(knobs: knobs, log: log))
            #expect(log.take() == ["200 → 200", "width 200, unrelated 0"])

            harness.host.setSize(Size(width: 120, height: 200))
            harness.host.update()
            #expect(log.take() == ["200 → 120", "width 120, unrelated 0"])

            // Built again, placed at the same width: nothing to report.
            knobs.unrelated = 1
            harness.host.update()
            #expect(log.take() == [])
        }

        @Test func aPreferenceFromInsideFollowsATransitionToItsEnd() async {
            let log = Log()
            let knobs = Knobs()
            knobs.isShown = false
            let harness = Harness(ArrivingReader(knobs: knobs, log: log))
            _ = log.take()

            withAnimation(.linear(duration: 0.05)) { knobs.isShown = true }
            for _ in 0..<8 {
                await harness.settle(0.02)
            }
            let reported = log.take()
            // Built where the transition starts it, then — in passes that
            // only lay the transition out — built again on the way in, and
            // reported each time, up to where it comes to rest.
            #expect(reported.first == "at 100")
            #expect(reported.count > 2)
            #expect(reported.last == "at 0")
        }
    }
}
