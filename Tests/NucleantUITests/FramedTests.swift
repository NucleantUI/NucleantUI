//
//  FramedTests.swift
//  NucleantUITests
//
//  `.framed(_:alignment:)`: the view inside lands in the rect, measured in
//  the parent's space, exactly where `.frame(width:height:alignment:)` and
//  then `.position` at the rect's center would put it — and the framed view
//  takes the room its parent offers, as a positioned one does.
//

import Testing
@testable import NucleantUI

/// A target laid out in `rect`, by `.framed` or by the `.frame` + `.position`
/// it stands for. `child` sizes the target inside the rect; `nil` fills it.
@View
struct FramedProbe {
    let log: Log
    let rect: Rect
    let alignment: Alignment
    let child: Size?
    let composed: Bool

    var body: some View {
        if composed {
            Color.red
                .frame(width: child?.width, height: child?.height)
                .onTapGesture { log("target") }
                .frame(width: rect.width, height: rect.height, alignment: alignment)
                .position(x: rect.midX, y: rect.midY)
        } else {
            Color.red
                .frame(width: child?.width, height: child?.height)
                .onTapGesture { log("target") }
                .framed(rect, alignment: alignment)
        }
    }
}

/// A probe in a vertical scroll view, over a footer: the scroll axis offers
/// no height, so the framed view is as tall as its rect there.
@View
struct ScrolledFramedProbe {
    let log: Log
    let rect: Rect
    let composed: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FramedProbe(log: log, rect: rect, alignment: .center, child: nil, composed: composed)
                Color.gray
                    .frame(height: 30)
                    .onTapGesture { log("footer") }
            }
        }
    }
}

/// Padding outside the modifier moves the space the rect is measured in.
@View
struct PaddedFramed {
    let log: Log

    var body: some View {
        Color.red
            .onTapGesture { log("target") }
            .framed(Rect(x: 10, y: 10, width: 20, height: 20))
            .padding(50)
    }
}

/// A framed view in a stack takes the room the fixed rows leave.
@View
struct FramedInStack {
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            Color.red
                .onTapGesture { log("target") }
                .framed(Rect(x: 90, y: 0, width: 20, height: 20))
            Color.gray
                .frame(height: 50)
                .onTapGesture { log("footer") }
        }
    }
}

/// Each tap moves the target to the other rect, which is a different size.
@View
struct MovingFramed {
    let log: Log
    @State private var isAtStart = true

    var body: some View {
        Color.red
            .onTapGesture {
                log(isAtStart ? "start" : "end")
                isAtStart.toggle()
            }
            .framed(isAtStart
                ? Rect(x: 10, y: 10, width: 30, height: 20)
                : Rect(x: 120, y: 100, width: 60, height: 80))
    }
}

extension Harness {
    /// A tap without waiting on timers — a plain tap gesture ends on release.
    func probe(_ point: Point) {
        host.pointerDown(id: 0, at: point)
        host.pointerUp(id: 0, at: point)
        _ = host.update()
    }
}

/// Points half a point either side of each edge of `rect`, and its middle,
/// in every combination across the two axes.
private func probes(around rect: Rect) -> [Point] {
    let xs = [rect.minX - 0.5, rect.minX + 0.5, rect.midX, rect.maxX - 0.5, rect.maxX + 0.5]
    let ys = [rect.minY - 0.5, rect.minY + 0.5, rect.midY, rect.maxY - 0.5, rect.maxY + 0.5]
    return xs.flatMap { x in ys.map { y in Point(x: x, y: y) } }
}

extension HostedViews {
    @MainActor
    @Suite
    struct FramedTests {

        /// Rect, alignment and the target's own size, if it has one: filling,
        /// smaller and aligned, larger than the rect, partly off screen, and
        /// at fractional coordinates.
        static let cases: [(Rect, Alignment, Size?)] = [
            (Rect(x: 40, y: 30, width: 100, height: 50), .center, nil),
            (Rect(x: 40, y: 30, width: 100, height: 50), .center, Size(width: 20, height: 10)),
            (Rect(x: 25, y: 120, width: 60, height: 40), .bottomTrailing, Size(width: 20, height: 10)),
            (Rect(x: 50, y: 60, width: 100, height: 80), .topLeading, Size(width: 20, height: 20)),
            (Rect(x: 10, y: 10, width: 50, height: 50), .topLeading, Size(width: 80, height: 30)),
            (Rect(x: -20, y: 150, width: 90, height: 70), .center, nil),
            (Rect(x: 33.5, y: 47.25, width: 61.5, height: 22.75), .trailing, Size(width: 12.5, height: 8)),
        ]

        @Test func targetLandsInTheRectByAlignment() {
            for (rect, alignment, child) in Self.cases {
                let expected = alignment.position(child ?? rect.size, in: rect)
                let log = Log()
                let harness = Harness(FramedProbe(log: log, rect: rect, alignment: alignment, child: child, composed: false))
                let window = Rect(x: 0, y: 0, width: 200, height: 200)
                for point in probes(around: expected) where window.contains(point) {
                    harness.probe(point)
                    #expect(log.take() == (expected.contains(point) ? ["target"] : []), "\(rect) \(alignment) at \(point)")
                }
            }
        }

        @Test func sameAsFrameThenPosition() {
            for (rect, alignment, child) in Self.cases {
                let expected = alignment.position(child ?? rect.size, in: rect)
                let points = probes(around: expected) + probes(around: rect)
                let framedLog = Log()
                let composedLog = Log()
                let framed = Harness(FramedProbe(log: framedLog, rect: rect, alignment: alignment, child: child, composed: false))
                let composed = Harness(FramedProbe(log: composedLog, rect: rect, alignment: alignment, child: child, composed: true))
                for point in points {
                    framed.probe(point)
                    composed.probe(point)
                    #expect(framedLog.take() == composedLog.take(), "\(rect) \(alignment) at \(point)")
                }
            }
        }

        @Test func asTallAsItsRectWhereNoHeightIsOffered() {
            let rect = Rect(x: 30, y: 40, width: 80, height: 60)
            let framedLog = Log()
            let composedLog = Log()
            let framed = Harness(ScrolledFramedProbe(log: framedLog, rect: rect, composed: false))
            let composed = Harness(ScrolledFramedProbe(log: composedLog, rect: rect, composed: true))
            // The footer starts where the rect's height ends, not its maxY,
            // and is drawn over the part of the target that hangs past it.
            framed.probe(Point(x: 10, y: 75))
            framed.probe(Point(x: 70, y: 50))
            framed.probe(Point(x: 70, y: 70))
            #expect(framedLog.take() == ["footer", "target", "footer"])
            for point in probes(around: rect) + [Point(x: 10, y: 59), Point(x: 10, y: 61), Point(x: 10, y: 89), Point(x: 10, y: 91)] {
                framed.probe(point)
                composed.probe(point)
                #expect(framedLog.take() == composedLog.take(), "at \(point)")
            }
        }

        @Test func rectIsInTheParentsSpace() async {
            let log = Log()
            let harness = Harness(PaddedFramed(log: log))
            await harness.tap(Point(x: 20, y: 20))
            #expect(log.take() == [])
            await harness.tap(Point(x: 61, y: 61))
            await harness.tap(Point(x: 79, y: 79))
            #expect(log.take() == ["target", "target"])
            await harness.tap(Point(x: 81, y: 70))
            #expect(log.take() == [])
        }

        @Test func takesTheRoomTheStackLeaves() async {
            let log = Log()
            let harness = Harness(FramedInStack(log: log))
            await harness.tap(Point(x: 100, y: 10))
            await harness.tap(Point(x: 100, y: 175))
            await harness.tap(Point(x: 100, y: 140))
            #expect(log.take() == ["target", "footer"])
        }

        @Test func movesAndResizesWhenTheRectChanges() async {
            let log = Log()
            let harness = Harness(MovingFramed(log: log))
            await harness.tap(Point(x: 35, y: 25))
            await harness.tap(Point(x: 35, y: 25))
            await harness.tap(Point(x: 175, y: 175))
            #expect(log.take() == ["start", "end"])
        }
    }
}
