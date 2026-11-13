//
//  AppearanceEffectTests.swift
//  NucleantUITests
//
//  `onAppear`, `onDisappear` and `.onChange` over a view's life, hosted:
//  each fires once per appearance and not once per rebuild; a view that
//  leaves — a row removed, another view standing in its place — is
//  forgotten, and one that comes back starts afresh.
//

import Observation
import Testing
@testable import NucleantUI

@MainActor
@Observable
final class Shelf {
    var items: [Int] = [1, 2, 3]
    var value = 0
}

@View
struct ShelfRows {
    let shelf: Shelf
    let log: Log

    var body: some View {
        VStack(spacing: 0) {
            ForEach(shelf.items, id: \.self) { item in
                Color.orange
                    .frame(width: 10, height: 10)
                    .onAppear { log("appear \(item)") }
                    .onDisappear { log("disappear \(item)") }
                    .onChange(of: shelf.value) { old, new in
                        log("\(item): \(old) → \(new)")
                    }
            }
        }
    }
}

/// One position that holds a color or a text, as `knobs.isShown` says:
/// the same path, a view of another type in it.
@View
struct SwappedInPlace {
    let knobs: Knobs
    let log: Log

    var body: some View {
        // Read, so a change of it builds this view again with the same
        // views in it.
        let _ = knobs.value
        AnyView(
            knobs.isShown
                ? AnyView(Color.orange.onAppear { log("color appears") }.onDisappear { log("color leaves") })
                : AnyView(Text("x").onAppear { log("text appears") }.onDisappear { log("text leaves") })
        )
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct AppearanceEffectTests {

        @Test func eachRowAppearsOnceAndIsForgottenWhenItLeaves() async {
            let shelf = Shelf()
            let log = Log()
            let harness = Harness(ShelfRows(shelf: shelf, log: log))
            #expect(log.take() == ["appear 1", "appear 2", "appear 3"])

            await harness.change { shelf.value = 1 }
            #expect(log.take() == ["1: 0 → 1", "2: 0 → 1", "3: 0 → 1"], "a rebuild is no new appearance")

            await harness.change { shelf.items = [1, 3] }
            #expect(log.take() == ["disappear 2"])

            await harness.change { shelf.items = [1, 2, 3] }
            #expect(log.take() == ["appear 2"], "back, it appears again")

            await harness.change { shelf.value = 2 }
            #expect(
                log.take() == ["1: 1 → 2", "2: 1 → 2", "3: 1 → 2"],
                "the row that came back compares with what it saw when it came back"
            )
        }

        @Test func severalRowsLeavingTogetherEachDisappear() async {
            let shelf = Shelf()
            shelf.items = Array(1...6)
            let log = Log()
            let harness = Harness(ShelfRows(shelf: shelf, log: log))
            _ = log.take()

            await harness.change { shelf.items = [1, 6] }
            #expect(Set(log.take()) == ["disappear 2", "disappear 3", "disappear 4", "disappear 5"])

            await harness.change { shelf.items = [] }
            #expect(Set(log.take()) == ["disappear 1", "disappear 6"])
        }

        @Test func anotherViewInTheSamePlaceIsANewAppearance() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(SwappedInPlace(knobs: knobs, log: log))
            #expect(log.take() == ["color appears"])

            await harness.change { knobs.isShown = false }
            #expect(log.take() == ["color leaves", "text appears"])

            await harness.change { knobs.isShown = true }
            #expect(log.take() == ["text leaves", "color appears"])

            await harness.change { knobs.value += 1 }
            #expect(log.take().isEmpty, "built again, the same views stay")
        }
    }
}

/// Rows whose closure logs each time it runs, under a parent that
/// `shelf.value` runs again.
@View
struct LoggedRowClosure {
    let shelf: Shelf
    let log: Log

    var body: some View {
        // Read, so a change of it runs this body again.
        let _ = shelf.value
        VStack(spacing: 0) {
            ForEach(shelf.items, id: \.self) { item in
                row(item)
            }
        }
    }

    private func row(_ item: Int) -> some View {
        log("row \(item)")
        return Color.orange.frame(width: 10, height: 10)
    }
}

/// Rows whose closure captures a value the parent works out from
/// `shelf.value`.
@View
struct CapturingRowClosure {
    let shelf: Shelf
    let log: Log

    var body: some View {
        let mark = shelf.value % 2 == 0 ? "even" : "odd"
        VStack(spacing: 0) {
            ForEach(shelf.items, id: \.self) { item in
                row(item, mark)
            }
        }
    }

    private func row(_ item: Int, _ mark: String) -> some View {
        log("row \(item) \(mark)")
        return Color.orange.frame(width: 10, height: 10)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ForEachEquivalenceTests {

        @Test func aCaptureThatChangedBuildsTheRowsAgain() async {
            let shelf = Shelf()
            shelf.items = [1, 2]
            let log = Log()
            let harness = Harness(CapturingRowClosure(shelf: shelf, log: log))
            #expect(log.take() == ["row 1 even", "row 2 even"])

            await harness.change { shelf.value = 2 }
            #expect(log.take().isEmpty, "the capture came out the same")

            await harness.change { shelf.value = 3 }
            #expect(log.take() == ["row 1 odd", "row 2 odd"], "the closure captured another value")
        }

        @Test func theSameRowsAreNotBuiltAgain() async {
            let shelf = Shelf()
            let log = Log()
            let harness = Harness(LoggedRowClosure(shelf: shelf, log: log))
            #expect(log.take() == ["row 1", "row 2", "row 3"])

            await harness.change { shelf.value += 1 }
            #expect(log.take().isEmpty, "the same data and closure: no row closure runs")

            await harness.change { shelf.items = [1, 3] }
            #expect(log.take() == ["row 1", "row 3"], "other data: each row closure runs")
        }
    }
}
