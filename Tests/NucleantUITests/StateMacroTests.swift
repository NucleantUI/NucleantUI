//
//  StateMacroTests.swift
//  NucleantUITests
//
//  `@State`'s initial value is made when the state is created — once per
//  view at a place in the tree — not each time the view's struct is
//  constructed. And the forms an `@State` property can take — inferred or
//  declared type, optional, no initial value, observers, assigned in an
//  initializer — still read, write and bind like state.
//

import Observation
import Testing
@testable import NucleantUI

/// How many initial values have been made, by kind.
@MainActor
private enum Made {
    static var models = 0
    static var tallies = 0

    static func reset() {
        models = 0
        tallies = 0
    }

    static func tally() -> Int {
        tallies += 1
        return 0
    }
}

@MainActor
@Observable
private final class Model {
    var count = 0

    init() {
        Made.models += 1
    }
}

// MARK: - Views

/// A model with an inferred type (private, so only the macro's storage
/// makes it) and a value with a declared one (internal, so `@View`'s
/// initializer takes it). Tapping bumps the model.
@View
private struct Child {
    let tick: Int
    let log: Log
    @State private var model = Model()
    @State var tally: Int = Made.tally()

    var body: some View {
        let _ = log("child \(tick) model \(model.count) id \(ObjectIdentifier(model).hashValue)")
        Color.blue
            .frame(width: 200, height: 100)
            .onTapGesture { model.count += 1 }
    }
}

/// The top half rebuilds the parent (and so constructs a new `Child`); a
/// tap at the top-left corner removes the child, the next brings a new one.
@View
private struct Parent {
    let log: Log
    @State private var tick = 0
    @State private var showsChild = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.red
                    .frame(width: 100, height: 100)
                    .onTapGesture { showsChild.toggle() }
                Color.gray
                    .frame(width: 100, height: 100)
                    .onTapGesture { tick += 1 }
            }
            if showsChild {
                Child(tick: tick, log: log)
            } else {
                Color.clear.frame(width: 200, height: 100)
            }
        }
    }
}

/// `self.value = start` in an initializer, for a property with an initial
/// value and for one without.
@View
private struct Assigned {
    let start: Int
    let log: Log
    @State private var value = -1
    @State private var label: String
    @State private var other: Int

    init(start: Int, log: Log, _viewID: ViewID = #viewID) {
        self.start = start
        self.log = log
        self.label = "start \(start)"
        self.other = start * 10
        self.value = start
        self._viewID = _viewID
    }

    var body: some View {
        let _ = log("\(start): \(label) value \(value) other \(other)")
        Color.blue
            .frame(width: 200, height: 100)
            .onTapGesture { value += 1 }
    }
}

/// Rebuilds `Assigned` with a new `start` each time the top half is tapped.
@View
private struct AssignedParent {
    let log: Log
    @State private var start = 1

    var body: some View {
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 100)
                .onTapGesture { start += 1 }
            Assigned(start: start, log: log)
        }
    }
}

/// Observers declared on an `@State` property run around a write.
@View
private struct Observed {
    let log: Log
    @State private var count = 0 {
        willSet { log("will \(count) -> \(newValue)") }
        didSet(previous) { log("did \(previous) -> \(count)") }
    }

    var body: some View {
        Color.blue
            .frame(width: 200, height: 200)
            .onTapGesture { count += 1 }
    }
}

/// Writes through the binding it is handed.
@View
private struct Editor {
    @Binding var text: String

    var body: some View {
        Color.blue
            .frame(width: 200, height: 100)
            .onTapGesture { text += "!" }
    }
}

/// `$text` of an inferred type, `$picked` of an optional with no initial
/// value: both projections bind to the state.
@View
private struct Projections {
    let log: Log
    @State private var text = "hi"
    @State private var picked: String?

    var body: some View {
        let _ = log("\(text) \(picked ?? "none")")
        VStack(spacing: 0) {
            Editor(text: $text)
            Color.gray
                .frame(width: 200, height: 100)
                .onTapGesture { $picked.wrappedValue = "picked" }
        }
    }
}

// MARK: - Tests

extension HostedViews {

    @MainActor
    @Suite
    struct StateMacro {
        let toggle = Point(x: 50, y: 50)
        let rebuild = Point(x: 150, y: 50)
        let bottom = Point(x: 100, y: 150)
        let top = Point(x: 100, y: 50)

        @Test func constructingAViewMakesNoInitialValue() {
            Made.reset()
            let log = Log()
            for tick in 0..<3 {
                _ = Child(tick: tick, log: log)
            }
            _ = Child(tick: 0, log: log, tally: Made.tally() + 5)
            #expect(Made.models == 0)
            #expect(Made.tallies == 0)
        }

        @Test func theInitialValueIsMadeOnceForTheView() async {
            Made.reset()
            let log = Log()
            let harness = Harness(Parent(log: log))
            #expect(Made.models == 1)
            #expect(Made.tallies == 1)
            log.take()

            for _ in 0..<5 {
                await harness.tap(rebuild)
            }
            // The child was rebuilt for each new tick — a new struct each
            // time — and kept the model it started with.
            #expect(log.take().map { $0.prefix(7) } == ["child 1", "child 2", "child 3", "child 4", "child 5"])
            #expect(Made.models == 1)
            #expect(Made.tallies == 1)
        }

        @Test func theStateKeepsItsInstanceAcrossRebuilds() async {
            Made.reset()
            let log = Log()
            let harness = Harness(Parent(log: log))
            let first = log.take().last.map { String($0.split(separator: " ").last!) }

            await harness.tap(bottom)
            await harness.tap(rebuild)
            await harness.tap(bottom)
            let entries = log.take()
            #expect(entries.last?.hasPrefix("child 1 model 2") == true)
            #expect(entries.allSatisfy { $0.hasSuffix(" \(first!)") })
        }

        @Test func aNewViewInTheSamePlaceGetsAFreshValue() async {
            Made.reset()
            let log = Log()
            let harness = Harness(Parent(log: log))
            await harness.tap(bottom)
            await harness.tap(toggle)   // child gone
            await harness.tap(toggle)   // a new one
            #expect(Made.models == 2)
            #expect(log.take().last?.hasPrefix("child 0 model 0") == true)
        }

        @Test func anInitializerAssignmentIsTheInitialValueOnce() async {
            let log = Log()
            let harness = Harness(AssignedParent(log: log))
            #expect(log.take() == ["1: start 1 value 1 other 10"])

            await harness.tap(bottom)
            #expect(log.take() == ["1: start 1 value 2 other 10"])

            // A new `start`: the struct is built with it, the state is not.
            await harness.tap(top)
            #expect(log.take() == ["2: start 1 value 2 other 10"])
        }

        @Test func observersRunAroundAWrite() async {
            let log = Log()
            let harness = Harness(Observed(log: log))
            await harness.tap(center)
            await harness.tap(center)
            #expect(log.take() == ["will 0 -> 1", "did 0 -> 1", "will 1 -> 2", "did 1 -> 2"])
        }

        @Test func projectionsBindToTheState() async {
            let log = Log()
            let harness = Harness(Projections(log: log))
            #expect(log.take() == ["hi none"])

            await harness.tap(top)
            #expect(log.take() == ["hi! none"])

            await harness.tap(bottom)
            #expect(log.take() == ["hi! picked"])
        }
    }
}
