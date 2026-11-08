//
//  ChangeDetectionTests.swift
//  NucleantUITests
//
//  What a change rebuilds, and what it leaves standing: an equal write is no
//  write, plain data compares by its bytes, and a view whose inputs did not
//  change is not built again (plans/change-detection.md).
//

import Testing
@testable import NucleantUI

// MARK: - Equal writes

/// Writes `0` over the `0` it holds, or `1`.
@View
private struct Rewriter {
    let log: Log
    @State private var value = 0

    var body: some View {
        let _ = log("body \(value)")
        VStack(spacing: 0) {
            Color.blue
                .frame(width: 200, height: 100)
                .onTapGesture { value = 0 }
            Color.red
                .frame(width: 200, height: 100)
                .onTapGesture { value = 1 }
        }
    }
}

private struct Track: Equatable {
    var level: Int
}

/// Two faders, each bound into one element of the mixer's array.
@View
private struct Mixer {
    let log: Log
    @State private var tracks = [Track(level: 1), Track(level: 2)]

    var body: some View {
        let _ = log("mixer")
        VStack(spacing: 0) {
            ForEach([0, 1], id: \.self) { index in
                Fader(level: $tracks[index].level, log: log)
            }
        }
    }
}

/// Sets its level to 1 when tapped.
@View
private struct Fader {
    @Binding var level: Int
    let log: Log

    var body: some View {
        let _ = log("fader \(level)")
        Color.blue
            .frame(width: 200, height: 100)
            .onTapGesture { level = 1 }
    }
}

/// An animated write of the value already there, with a completion.
@View
private struct AnimatedRewriter {
    let log: Log
    @State private var value = 0

    var body: some View {
        let _ = log("body \(value)")
        Color.blue
            .frame(width: 200, height: 200)
            .onTapGesture {
                withAnimation {
                    value = 0
                } completion: {
                    log("done")
                }
            }
    }
}

private final class Box {}

/// Writes back the object it already holds.
@View
private struct ObjectRewriter {
    let log: Log
    @State private var box = Box()

    var body: some View {
        let _ = log("body")
        Color.blue
            .frame(width: 200, height: 200)
            .onTapGesture {
                let same = box
                box = same
            }
    }
}

/// A value with no `Equatable` that is not plain data — nothing says how to
/// compare it.
private struct Note {
    var text: String
}

@View
private struct NoteRewriter {
    let log: Log
    @State private var note = Note(text: "a")

    var body: some View {
        let _ = log("note \(note.text)")
        Color.blue
            .frame(width: 200, height: 200)
            .onTapGesture { note = Note(text: "a") }
    }
}

// MARK: - Plain data

/// Plain data with no `Equatable`.
private struct Spot {
    var x: Int
    var y: Double
}

@View
private struct HoldsSpot {
    let spot: Spot
    let log: Log

    var body: some View {
        let _ = log("child \(spot.x)")
        Color.green.frame(width: 200, height: 100)
    }
}

/// Re-runs on the top tap with its child's input unchanged, moves the
/// child's spot on the bottom one.
@View
private struct SpotParent {
    let log: Log
    @State private var tick = 0
    @State private var spot = Spot(x: 0, y: 0.5)

    var body: some View {
        let _ = log("parent \(tick)")
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { tick += 1 }
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { spot.x += 1 }
            HoldsSpot(spot: spot, log: log)
        }
    }
}

// MARK: - Environment

private struct LevelKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var level: Int {
        get { self[LevelKey.self] }
        set { self[LevelKey.self] = newValue }
    }
}

/// Puts its `level` into the environment of four children: one reads it,
/// one never does, one reads it only once tapped, inside a view that reads
/// nothing itself.
@View
private struct LevelParent {
    let log: Log
    @State private var level = 0

    var body: some View {
        let _ = log("parent \(level)")
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { level += 1 }
            LevelReader(log: log)
            NoReader(log: log)
            Holder(log: log)
        }
        .environment(\.level, level)
    }
}

@View
private struct LevelReader {
    let log: Log
    @Environment(\.level) private var level

    var body: some View {
        let _ = log("reader \(level)")
        Color.blue.frame(width: 200, height: 50)
    }
}

@View
private struct NoReader {
    let log: Log

    var body: some View {
        let _ = log("none")
        Color.green.frame(width: 200, height: 50)
    }
}

@View
private struct Holder {
    let log: Log

    var body: some View {
        let _ = log("holder")
        LateReader(log: log)
    }
}

/// Reads the level only once tapped, through a child it did not have.
@View
private struct LateReader {
    let log: Log
    @State private var shown = false

    var body: some View {
        let _ = log("late")
        VStack(spacing: 0) {
            Color.orange
                .frame(width: 200, height: 25)
                .onTapGesture { shown = true }
            if shown {
                LevelLogger(log: log)
            }
        }
        .frame(height: 50, alignment: .top)
    }
}

@View
private struct LevelLogger {
    let log: Log
    @Environment(\.level) private var level

    var body: some View {
        let _ = log("logger \(level)")
        Color.purple.frame(width: 200, height: 25)
    }
}

/// A `GeometryReader` that reads the level only once it is narrow — made
/// narrow by a sibling, so the reader is built again during placement,
/// never by its parent.
@View
private struct SqueezeParent {
    let log: Log
    @State private var level = 0

    var body: some View {
        let _ = log("parent \(level)")
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { level += 1 }
            Squeezer(log: log)
        }
        .environment(\.level, level)
    }
}

@View
private struct Squeezer {
    let log: Log
    @State private var narrow = false

    var body: some View {
        HStack(spacing: 0) {
            Color.red
                .frame(width: narrow ? 150 : 50, height: 50)
                .onTapGesture { narrow = true }
            WidthProbe(log: log)
        }
        .frame(width: 200, height: 50)
    }
}

@View
private struct WidthProbe {
    let log: Log

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width < 100 {
                LevelLogger(log: log)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Who a write rebuilds

/// Declares the state but never reads it: it only hands `$value` down.
@View
private struct PassesBinding {
    let log: Log
    @State private var value = 0

    var body: some View {
        let _ = log("owner")
        BoundCounter(value: $value, log: log)
    }
}

@View
private struct BoundCounter {
    @Binding var value: Int
    let log: Log

    var body: some View {
        let _ = log("child \(value)")
        Color.blue
            .frame(width: 200, height: 200)
            .onTapGesture { value += 1 }
    }
}

/// Reads its state only inside a shape's closure, which runs as the shape
/// is placed — no `body` reads it.
@View
private struct DrawsState {
    let log: Log
    @State private var width = 50.0

    var body: some View {
        let _ = log("owner")
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 100)
                .onTapGesture { width = 150 }
            PathShape { size in
                log("path \(Int(width))")
                return Path()
            }
            .frame(width: 200, height: 100)
        }
    }
}

/// Ten rows of 100 points in a 200-point scroll view, eager or lazy, each
/// logging its index when tapped.
@View
private struct ScrolledRows {
    let lazy: Bool
    let log: Log

    var body: some View {
        ScrollView {
            if lazy {
                LazyVStack(spacing: 0) { rows }
            } else {
                VStack(spacing: 0) { rows }
            }
        }
    }

    private var rows: some View {
        ForEach(0..<10, id: \.self) { index in
            Color.blue
                .frame(width: 200, height: 100)
                .onTapGesture { log("row \(index)") }
        }
    }
}

@MainActor
@Suite
struct PlainDataEquivalence {

    @Test func plainDataComparesByItsBytes() {
        let log = Log()
        #expect(HoldsSpot(spot: Spot(x: 1, y: 2), log: log)
            ._isEquivalent(to: HoldsSpot(spot: Spot(x: 1, y: 2), log: log)))
        #expect(!HoldsSpot(spot: Spot(x: 1, y: 2), log: log)
            ._isEquivalent(to: HoldsSpot(spot: Spot(x: 2, y: 2), log: log)))
        #expect(!HoldsSpot(spot: Spot(x: 1, y: 2), log: log)
            ._isEquivalent(to: HoldsSpot(spot: Spot(x: 1, y: 3), log: log)))
    }

    @Test func plainDataWithNoFieldsIsAlwaysTheSame() {
        struct Nothing {}
        #expect(_areEquivalent(Nothing(), Nothing()))
    }

    @Test func aValueThatIsNotPlainDataStillCannotBeCompared() {
        #expect(!_areEquivalent(Note(text: "a"), Note(text: "a")))
    }

    @Test func plainDataEnumsCompareCaseAndPayload() {
        enum Mark { case dot, line(Int), box(Double, Double) }
        #expect(_areEquivalent(Mark.line(3), Mark.line(3)))
        #expect(!_areEquivalent(Mark.line(3), Mark.line(4)))
        #expect(!_areEquivalent(Mark.dot, Mark.line(0)))
        #expect(_areEquivalent(Mark.box(1, 2), Mark.box(1, 2)))
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct EqualWrites {

        @Test func writingTheValueAlreadyThereRebuildsNothing() async {
            let log = Log()
            let harness = Harness(Rewriter(log: log))
            #expect(log.take() == ["body 0"])
            await harness.tap(Point(x: 100, y: 50))
            #expect(log.take() == [])
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == ["body 1"])
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == [])
        }

        @Test func anEqualWriteThroughABindingChainRebuildsNothing() async {
            let log = Log()
            let harness = Harness(Mixer(log: log))
            #expect(log.take() == ["mixer", "fader 1", "fader 2"])
            await harness.tap(Point(x: 100, y: 50))     // 1 over 1
            #expect(log.take() == [])
            await harness.tap(Point(x: 100, y: 150))    // 1 over 2
            #expect(log.take() == ["fader 1"])     // the mixer only hands bindings down
            await harness.tap(Point(x: 100, y: 150))    // 1 over 1 again
            #expect(log.take() == [])
        }

        @Test func anAnimationWhoseWritesWereAllEqualStillCompletes() async {
            let log = Log()
            let harness = Harness(AnimatedRewriter(log: log))
            #expect(log.take() == ["body 0"])
            await harness.tap(center)
            await harness.settle()
            #expect(log.take() == ["done"])
        }

        @Test func writingBackTheSameObjectRebuildsNothing() async {
            let log = Log()
            let harness = Harness(ObjectRewriter(log: log))
            #expect(log.take() == ["body"])
            await harness.tap(center)
            #expect(log.take() == [])
        }

        @Test func aValueThatCannotBeComparedAlwaysCountsAsChanged() async {
            let log = Log()
            let harness = Harness(NoteRewriter(log: log))
            #expect(log.take() == ["note a"])
            await harness.tap(center)
            #expect(log.take() == ["note a"])
        }
    }

    @MainActor
    @Suite
    struct EnvironmentReadsPerValue {

        @Test func onlyTheViewsThatReadAChangedValueAreRebuilt() async {
            let log = Log()
            let harness = Harness(LevelParent(log: log))
            #expect(log.take() == ["parent 0", "reader 0", "none", "holder", "late"])
            await harness.tap(Point(x: 100, y: 25))
            #expect(log.take() == ["parent 1", "reader 1"])
        }

        @Test func aViewKeptUnderAChangedValueSeesItWhenItFirstReadsIt() async {
            let log = Log()
            let harness = Harness(LevelParent(log: log))
            _ = log.take()
            await harness.tap(Point(x: 100, y: 25))     // level 1; the late reader is kept
            #expect(log.take() == ["parent 1", "reader 1"])
            await harness.tap(Point(x: 100, y: 160))    // it reads the level now
            #expect(log.take() == ["late", "logger 1"])
        }

        @Test func aReadMadeInARebuildBelowReachesTheViewsAbove() async {
            let log = Log()
            let harness = Harness(LevelParent(log: log))
            _ = log.take()
            await harness.tap(Point(x: 100, y: 160))    // the late reader reads the level
            #expect(log.take() == ["late", "logger 0"])
            await harness.tap(Point(x: 100, y: 25))     // so its holder is not kept
            #expect(log.take() == ["parent 1", "reader 1", "holder", "late", "logger 1"])
        }

        @Test func aGeometryReaderBuiltDuringPlacementSeesTheValueItStandsUnder() async {
            let log = Log()
            let harness = Harness(SqueezeParent(log: log))
            #expect(log.take() == ["parent 0"])
            await harness.tap(Point(x: 100, y: 25))     // level 1; the width probe is kept
            #expect(log.take() == ["parent 1"])
            await harness.tap(Point(x: 25, y: 75))      // the width probe narrows, and reads it
            #expect(log.take() == ["logger 1"])
            await harness.tap(Point(x: 100, y: 25))     // read during placement: not kept now
            #expect(log.take() == ["parent 2", "logger 2"])
        }
    }

    @MainActor
    @Suite
    struct WhoAWriteRebuilds {

        @Test func aViewThatOnlyPassesItsStateDownIsNotRebuilt() async {
            let log = Log()
            let harness = Harness(PassesBinding(log: log))
            #expect(log.take() == ["owner", "child 0"])
            await harness.tap(center)
            #expect(log.take() == ["child 1"])
            await harness.tap(center)
            #expect(log.take() == ["child 2"])
        }

        @Test func stateReadWhileDrawingStillRedraws() async {
            let log = Log()
            let harness = Harness(DrawsState(log: log))
            let first = log.take()
            #expect(first.first == "owner")
            #expect(first.contains("path 50"))
            await harness.tap(Point(x: 100, y: 50))
            let second = log.take()
            #expect(second.first == "owner")
            #expect(second.contains("path 150"))
            #expect(!second.contains("path 50"))
        }
        @Test(arguments: [false, true])
        func aScrollViewStillMovesItsContent(lazy: Bool) async {
            let log = Log()
            let harness = Harness(ScrolledRows(lazy: lazy, log: log))
            await harness.tap(Point(x: 100, y: 50))
            #expect(log.take() == ["row 0"])
            harness.host.pointerMoved(to: center)
            harness.host.scroll(dx: 0, dy: -500)
            await harness.settle()
            await harness.settle()
            await harness.tap(Point(x: 100, y: 50))
            #expect(log.take() == ["row 5"])
        }
    }

    @MainActor
    @Suite
    struct PlainDataInputs {

        @Test func aChildWithUnchangedPlainDataIsReused() async {
            let log = Log()
            let harness = Harness(SpotParent(log: log))
            #expect(log.take() == ["parent 0", "child 0"])
            await harness.tap(Point(x: 100, y: 25))
            #expect(log.take() == ["parent 1"])
            await harness.tap(Point(x: 100, y: 75))
            #expect(log.take() == ["parent 1", "child 1"])
        }
    }
}
