//
//  ModifierEquivalenceTests.swift
//  NucleantUITests
//
//  Each modifier is a type of its own, and two applications of one are the
//  same input when their values are: what decides whether the view under a
//  modifier is kept when its parent runs again.
//

import Testing
@testable import NucleantUI

/// A class put into the environment: the same object is the same value.
@MainActor
final class EnvironmentBox {}

/// A value that is `Equatable` and not `Hashable`.
struct Measure: Equatable {
    var points: Double
}

private struct BoxKey: EnvironmentKey {
    static let defaultValue: EnvironmentBox? = nil
}

private struct MeasureKey: EnvironmentKey {
    static let defaultValue = Measure(points: 0)
}

private struct ActionKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    fileprivate var box: EnvironmentBox? {
        get { self[BoxKey.self] }
        set { self[BoxKey.self] = newValue }
    }

    fileprivate var measure: Measure {
        get { self[MeasureKey.self] }
        set { self[MeasureKey.self] = newValue }
    }

    fileprivate var action: @Sendable () -> Void {
        get { self[ActionKey.self] }
        set { self[ActionKey.self] = newValue }
    }
}

@MainActor
@Suite
struct ModifierEquivalenceTests {

    @Test func modifiersOfPlainValuesCompareByThem() {
        func padded(_ amount: Double) -> some View { Color.orange.padding(amount) }
        #expect(padded(8)._isEquivalent(to: padded(8)))
        #expect(!padded(8)._isEquivalent(to: padded(9)))

        func framed(_ width: Double?) -> some View { Color.orange.frame(width: width, height: 10) }
        #expect(framed(20)._isEquivalent(to: framed(20)))
        #expect(!framed(20)._isEquivalent(to: framed(nil)))

        func moved(_ x: Double) -> some View { Color.orange.offset(x: x).opacity(0.5).rotationEffect(.degrees(x)) }
        #expect(moved(3)._isEquivalent(to: moved(3)))
        #expect(!moved(3)._isEquivalent(to: moved(4)))

        func styled(_ font: Font) -> some View { Text("a").font(font).foregroundStyle(.secondary).lineLimit(2) }
        #expect(styled(.body)._isEquivalent(to: styled(.body)))
        #expect(!styled(.body)._isEquivalent(to: styled(.title)))
    }

    @Test func theViewInsideCountsToo() {
        func label(_ text: String) -> some View { Text(text).padding(4) }
        #expect(label("a")._isEquivalent(to: label("a")))
        #expect(!label("a")._isEquivalent(to: label("b")))
    }

    @Test func anEnvironmentValueComparesAsAViewInput() {
        let box = EnvironmentBox()
        func boxed(_ box: EnvironmentBox) -> some View { Color.orange.environment(\.box, box) }
        #expect(boxed(box)._isEquivalent(to: boxed(box)), "the same object")
        #expect(!boxed(box)._isEquivalent(to: boxed(EnvironmentBox())), "another object")

        func measured(_ points: Double) -> some View { Color.orange.environment(\.measure, Measure(points: points)) }
        #expect(measured(2)._isEquivalent(to: measured(2)), "equal, though not hashable")
        #expect(!measured(2)._isEquivalent(to: measured(3)))

        func acting() -> some View { Color.orange.environment(\.action, {}) }
        #expect(!acting()._isEquivalent(to: acting()), "a closure is no telling")
    }

    @Test func anOptionalComparesByWhatItHolds() {
        let box = EnvironmentBox()
        #expect(_areEquivalent(Optional(box), Optional(box)), "the same object")
        #expect(!_areEquivalent(Optional(box), Optional(EnvironmentBox())), "another object")
        #expect(_areEquivalent(EnvironmentBox?.none, EnvironmentBox?.none), "neither holds one")
        #expect(!_areEquivalent(Optional(box), nil), "one holds one")
        #expect(_areEquivalent(Optional(Measure(points: 1)), Optional(Measure(points: 1))))
        #expect(!_areEquivalent(Optional(Measure(points: 1)), Optional(Measure(points: 2))))
    }

    @Test func aModifierHoldingAnActionIsBuiltAgain() {
        func tapped() -> some View { Color.orange.onTapGesture {} }
        #expect(!tapped()._isEquivalent(to: tapped()))
        func appearing() -> some View { Color.orange.onAppear {} }
        #expect(!appearing()._isEquivalent(to: appearing()))
    }
}

/// What an `AnyView` and the stores' boxes hold, compared and taken back
/// out as the type it is.
@MainActor
@Suite
struct ErasedStorageTests {

    @Test func anErasedViewComparesAsTheViewItHolds() {
        func erased(_ text: String) -> AnyView { AnyView(Text(text)) }
        func color() -> AnyView { AnyView(Color.orange) }
        #expect(erased("a")._isEquivalent(to: erased("a")))
        #expect(!erased("a")._isEquivalent(to: erased("b")))
        #expect(!erased("a")._isEquivalent(to: color()), "a view of another type")
        let one = erased("a")
        #expect(one._isEquivalent(to: one), "the same storage")
    }

    @Test func aBoxGivesItsValueBackOnlyAsItsType() {
        let box: AnyBox = Box(3)
        #expect(box.value(as: Int.self) == 3)
        #expect(box.value(as: Double.self) == nil)
        #expect(box.value(as: Int?.self) == nil, "an optional is another type")
        let optional: AnyBox = Box(Int?.none)
        #expect(optional.value(as: Int?.self) == .some(nil))
    }
}
