//
//  ClosureEquivalenceTests.swift
//  NucleantUITests
//
//  Two closures are the same input when they run the same code over
//  equivalent captures; a view holding a closure that captured a changed
//  value is built again, and runs the new closure.
//

import Testing
@testable import NucleantUI

private final class Object {}

/// Not `Equatable`, and holds a reference: nothing says how to compare it.
private struct Opaque {
    var name: String
}

private struct Point3: Equatable {
    var x, y, z: Double
}

// One spot each, so two calls make two closures of the same code.
private func capturing(_ value: Int) -> () -> Int { { value } }
private func capturing(_ value: String) -> () -> String { { value } }
private func capturing(_ value: Object) -> () -> ObjectIdentifier { { ObjectIdentifier(value) } }
private func capturing(_ value: Opaque) -> () -> String { { value.name } }
private func capturing(_ value: Point3, _ scale: Double, _ label: String) -> () -> String {
    { "\(label) \(value.x * scale)" }
}
private func capturingNothing() -> () -> Int { { 42 } }
private func otherCapturingNothing() -> () -> Int { { 7 } }
private func wrapping(_ inner: @escaping () -> Int) -> () -> Int { { inner() + 1 } }
@MainActor private func capturing(_ binding: Binding<Int>) -> @MainActor () -> Int { { binding.wrappedValue } }

// A view holds its closures in stored properties, and that is where they
// are compared — never passed along as generic values, which wraps them.
private struct Holds<Result> {
    let f: () -> Result
}

private struct HoldsInt {
    let f: () -> Int
}

private struct HoldsString {
    let f: () -> String
}

private struct HoldsIdentifier {
    let f: () -> ObjectIdentifier
}

private struct HoldsOptional {
    let f: (() -> Int)?
}

private struct HoldsMainActor {
    let f: @MainActor () -> Int
}

@MainActor
private func same(_ a: @escaping () -> Int, _ b: @escaping () -> Int) -> Bool {
    _areEquivalentClosures(HoldsInt(f: a), HoldsInt(f: b), \.f, name: "f")
}

@MainActor
private func same(_ a: @escaping () -> String, _ b: @escaping () -> String) -> Bool {
    _areEquivalentClosures(HoldsString(f: a), HoldsString(f: b), \.f, name: "f")
}

@MainActor
private func same(_ a: @escaping () -> ObjectIdentifier, _ b: @escaping () -> ObjectIdentifier) -> Bool {
    _areEquivalentClosures(HoldsIdentifier(f: a), HoldsIdentifier(f: b), \.f, name: "f")
}

@MainActor
@Suite
struct ClosureEquivalenceTests {

    // Each answer is worked out before `#expect` sees it: the macro takes a
    // call apart to show its arguments, and passing a closure along that way
    // wraps it — the very thing the comparison is built to avoid.

    @Test func equalCapturesAreTheSameInput() {
        let equal = same(capturing(3), capturing(3))
        let different = same(capturing(3), capturing(4))
        #expect(equal)
        #expect(!different)
    }

    @Test func aStringCapturedInNewStorageIsTheSame() {
        let a = ["a string long enough", "to live on the heap"].joined(separator: " ")
        let b = ["a string long enough to live", "on the heap"].joined(separator: " ")
        let equal = same(capturing(a), capturing(b))
        let different = same(capturing(a), capturing(a + "!"))
        #expect(equal)
        #expect(!different)
    }

    @Test func anObjectIsTheSameCaptureOnlyAsItself() {
        let object = Object()
        let equal = same(capturing(object), capturing(object))
        let different = same(capturing(object), capturing(Object()))
        #expect(equal)
        #expect(!different)
    }

    @Test func severalCapturesAllCount() {
        let point = Point3(x: 1, y: 2, z: 3)
        let equal = same(capturing(point, 2, "a"), capturing(point, 2, "a"))
        let otherScale = same(capturing(point, 2, "a"), capturing(point, 3, "a"))
        let otherLabel = same(capturing(point, 2, "a"), capturing(point, 2, "b"))
        let otherPoint = same(capturing(point, 2, "a"), capturing(Point3(x: 1, y: 2, z: 4), 2, "a"))
        #expect(equal)
        #expect(!otherScale)
        #expect(!otherLabel)
        #expect(!otherPoint)
    }

    @Test func closuresThatCapturedNothingCompareByTheirCode() {
        let equal = same(capturingNothing(), capturingNothing())
        let different = same(capturingNothing(), otherCapturingNothing())
        #expect(equal)
        #expect(!different)
    }

    @Test func aCapturedClosureCountsAsChanged() {
        // The descriptor names it by its lowered type, which no type
        // resolves from: there is nothing to compare it by.
        let equal = same(wrapping(capturing(1)), wrapping(capturing(1)))
        #expect(!equal)
    }

    @Test func aCaptureWithNoWayToCompareItCountsAsChanged() {
        let equal = same(capturing(Opaque(name: "a")), capturing(Opaque(name: "a")))
        #expect(!equal)
    }

    @Test func optionalClosures() {
        func same(_ a: (() -> Int)?, _ b: (() -> Int)?) -> Bool {
            _areEquivalentClosures(HoldsOptional(f: a), HoldsOptional(f: b), \.f, name: "f")
        }
        let bothAbsent = same(nil, nil)
        let oneAbsent = same(nil, capturing(1))
        let otherAbsent = same(capturing(1), nil)
        let equal = same(capturing(1), capturing(1))
        let different = same(capturing(1), capturing(2))
        #expect(bothAbsent)
        #expect(!oneAbsent)
        #expect(!otherAbsent)
        #expect(equal)
        #expect(!different)
    }

    @Test func aCapturedBindingComparesBySource() {
        func same(_ a: @escaping @MainActor () -> Int, _ b: @escaping @MainActor () -> Int) -> Bool {
            _areEquivalentClosures(HoldsMainActor(f: a), HoldsMainActor(f: b), \.f, name: "f")
        }
        // A binding from raw closures has no source: never the same input.
        let raw = Binding(get: { 1 }, set: { _ in })
        let equal = same(capturing(raw), capturing(raw))
        #expect(!equal)
    }

    @Test func aClosureValueWrappedToFitAGenericPropertyCountsAsChanged() {
        // `() -> Result` is stored as a generic function, so a `() -> Int`
        // handed to it as a value is wrapped in a thunk whose capture — the
        // closure — the descriptor names by its lowered type. A closure
        // literal written there is built for the property directly, and
        // compares (`aGenericViewsContentClosureKeepsItWhenUnchanged`).
        let equal = _areEquivalentClosures(Holds(f: capturing(3)), Holds(f: capturing(3)), \.f, name: "f")
        #expect(!equal)
    }
}

// MARK: - In a running tree

/// The `@View` docs' case: a row's action captures the id its parent had.
@View
private struct DeleteButton {
    let action: () -> Void
    let log: Log

    var body: some View {
        let _ = log("button")
        Color.red
            .frame(width: 200, height: 100)
            .onTapGesture { action() }
    }
}

@View
private struct UserRow {
    let log: Log
    @State private var userID = 1
    @State private var tick = 0

    var body: some View {
        let _ = log("row \(tick)")
        let id = userID
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { tick += 1 }
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { userID += 1 }
            DeleteButton(action: { log("delete \(id)") }, log: log)
        }
    }
}

/// A generic view keeping its content as a closure, the usual way.
@View
private struct Card<Content: View> {
    let log: Log
    let content: () -> Content

    var body: some View {
        let _ = log("card")
        content()
    }
}

@View
private struct CardParent {
    let log: Log
    @State private var tick = 0
    @State private var title = "a"

    var body: some View {
        let _ = log("parent \(tick)")
        let title = self.title
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { tick += 1 }
            Color.gray
                .frame(width: 200, height: 50)
                .onTapGesture { self.title = "b" }
            Card(log: log) {
                Text(title)
            }
        }
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct ClosureInputs {

        @Test func aClosureThatCapturedTheSameValueKeepsItsView() async {
            let log = Log()
            let harness = Harness(UserRow(log: log))
            #expect(log.take() == ["row 0", "button"])
            await harness.tap(Point(x: 100, y: 25))     // the row re-runs, same id
            #expect(log.take() == ["row 1"])
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == ["delete 1"])
        }

        @Test func aGenericViewsContentClosureKeepsItWhenUnchanged() async {
            let log = Log()
            let harness = Harness(CardParent(log: log))
            #expect(log.take() == ["parent 0", "card"])
            await harness.tap(Point(x: 100, y: 25))
            #expect(log.take() == ["parent 1"])
            await harness.tap(Point(x: 100, y: 75))
            #expect(log.take() == ["parent 1", "card"])
        }

        @Test func aClosureThatCapturedAChangedValueRunsTheNewOne() async {
            let log = Log()
            let harness = Harness(UserRow(log: log))
            _ = log.take()
            await harness.tap(Point(x: 100, y: 75))     // the id changes
            #expect(log.take() == ["row 0", "button"])
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == ["delete 2"])
        }
    }
}
