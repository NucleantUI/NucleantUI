//
//  Equivalence.swift
//  NucleantUI
//
//  "Would this view build the same tree as that one?" — the question behind
//  reusing a subtree instead of rebuilding it.
//
//  Equality is the wrong tool: a `Binding` is two closures, a `Button` holds
//  an action, and neither has a meaningful `==`. *Equivalence* is the weaker
//  claim the builder actually needs — same inputs from the view's point of
//  view. A binding is equivalent to another that points at the same state; a
//  closure is never equivalent to anything, because there is no way to tell.
//  Getting it wrong in the "equivalent" direction shows stale UI, so every
//  undecidable case answers no.
//

/// A type whose values can be compared for equivalence as view inputs.
///
/// Every `View` is one (`@View` generates the witness; a primitive without
/// one compares by `Equatable`); property wrappers and a few framework types
/// conform by hand. Anything else falls back to `Equatable` where available,
/// then to its bytes when it is plain data (`_isPOD`), and is otherwise not
/// equivalent — there is no reflection.
@MainActor
public protocol ViewInput {
    func _isEquivalent(to other: Self) -> Bool
}

// MARK: - Comparing two inputs

// Four overloads, so the generated `_isEquivalent` can write one call per
// property and let the compiler pick: the static path when the type is known
// to be `Equatable` or `ViewInput`, the dynamic one otherwise. The doubly
// constrained overload exists only to break the tie for a type that is both.

@MainActor
public func _areEquivalent<T: Equatable>(_ a: T, _ b: T) -> Bool {
    // Plain data with the same bytes is the same value, whatever `==` would
    // take the time to work out; different bytes still ask `==`, which may
    // call them equal (`-0.0` and `0.0`).
    if _isPOD(T.self), _plainBytesEqual(a, b) { return true }
    return a == b
}

@MainActor
public func _areEquivalent<T: ViewInput>(_ a: T, _ b: T) -> Bool {
    a._isEquivalent(to: b)
}

@MainActor
public func _areEquivalent<T: Equatable & ViewInput>(_ a: T, _ b: T) -> Bool {
    a._isEquivalent(to: b)
}

@MainActor
public func _areEquivalent<T>(_ a: T, _ b: T) -> Bool {
    if _isPOD(T.self), _plainBytesEqual(a, b) { return true }
    return _dynamicallyEquivalent(a, b)
}

/// Whether two values have the same bytes — a word at a time, then the
/// bytes left over. Only meaningful for plain data (`_isPOD`): a value
/// holding a reference has the reference's bytes, not what it refers to.
@inline(__always)
nonisolated func _plainBytesEqual<T>(_ a: T, _ b: T) -> Bool {
    withUnsafeBytes(of: a) { a in
        withUnsafeBytes(of: b) { b in
            let count = a.count
            var offset = 0
            while offset + 8 <= count {
                guard a.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                        == b.loadUnaligned(fromByteOffset: offset, as: UInt64.self) else { return false }
                offset += 8
            }
            while offset < count {
                guard a[offset] == b[offset] else { return false }
                offset += 1
            }
            return true
        }
    }
}

/// The runtime answer for a value whose static type says nothing.
///
/// Order matters: `ViewInput` first, so a `Binding` compares by source and
/// not through its `Equatable` conformance (which reads the value — and two
/// bindings onto the same slot always read the same value, changed or not).
///
/// Which of those applies depends only on the type, and asking costs a
/// protocol conformance lookup per question; so it is asked once per type,
/// and what to do with two values of that type is kept — see `comparator`.
@MainActor
func _dynamicallyEquivalent(_ a: Any, _ b: Any) -> Bool {
    let valueType = type(of: a)
    guard valueType == type(of: b) else { return false }
    let id = ObjectIdentifier(valueType)
    if let compare = comparators[id] {
        return compare(a, b)
    }
    let compare = comparator(for: a)
    comparators[id] = compare
    return compare(a, b)
}

/// How to compare two values, by their type.
@MainActor
private var comparators: [ObjectIdentifier: @MainActor (Any, Any) -> Bool] = [:]

/// How two values of `value`'s type compare — each is cast back to that
/// type, which a value of exactly that type always is.
@MainActor
private func comparator(for value: Any) -> @MainActor (Any, Any) -> Bool {
    if let value = value as? any ViewInput {
        return viewInputComparator(value)
    }
    // The same object is the same input: what a view reads *from* it is
    // tracked by observation, so a change inside it dirties the readers
    // without the reference having to look different. A different object
    // is a different input, whatever its contents.
    if type(of: value) is AnyClass {
        return { a, b in (a as AnyObject) === (b as AnyObject) }
    }
    if let value = value as? any Equatable {
        return equatableComparator(value)
    }
    // Plain data — no references, nothing retained, copied as its bytes —
    // is its bytes: equal bytes are the same value. Different bytes for the
    // same value (padding, `-0.0` and `0.0`) only cost a rebuild.
    if let compare = _openExistential(value, do: plainDataComparator) {
        return compare
    }
    // Nothing that says how to compare it: undecidable, so not equivalent.
    // A type that should compare declares `Equatable`.
    return { _, _ in false }
}

/// Compares two values of `T` by their bytes, when `T` is plain data.
private nonisolated func plainDataComparator<T>(_: T) -> (@MainActor (Any, Any) -> Bool)? {
    guard _isPOD(T.self) else { return nil }
    return { a, b in _plainBytesEqual(a as! T, b as! T) }
}

@MainActor
private func viewInputComparator<T: ViewInput>(_: T) -> @MainActor (Any, Any) -> Bool {
    { a, b in (a as! T)._isEquivalent(to: b as! T) }
}

@MainActor
private func equatableComparator<T: Equatable>(_: T) -> @MainActor (Any, Any) -> Bool {
    { a, b in _areEquivalent(a as! T, b as! T) }
}

// MARK: - Property wrappers

extension _StateProperty: ViewInput {
    /// Owned, not received: the value lives in the store and a write to it
    /// dirties this view directly. As an *input* it never changes.
    public func _isEquivalent(to other: _StateProperty<Value>) -> Bool { true }
}

extension Environment: ViewInput {
    /// The environment is compared by the builder before it ever asks about
    /// the view's own fields.
    public func _isEquivalent(to other: Environment<Value>) -> Bool { true }
}

extension Binding: ViewInput {
    /// Same source — the same state slot through the same key path. Not the
    /// same *value*: whether the value changed is tracked separately, by the
    /// reads the view made through this binding when its body last ran.
    public func _isEquivalent(to other: Binding<Value>) -> Bool {
        guard let source, let otherSource = other.source else { return false }
        return source == otherSource
    }
}

// MARK: - Structural views

extension TupleView {
    public func _isEquivalent(to other: TupleView<repeat each T>) -> Bool {
        for (a, b) in repeat (each value, each other.value) {
            guard _areEquivalent(a, b) else { return false }
        }
        return true
    }
}

extension _ViewArray {
    public func _isEquivalent(to other: _ViewArray<Content>) -> Bool {
        guard elements.count == other.elements.count else { return false }
        for (a, b) in zip(elements, other.elements) {
            guard _areEquivalent(a, b) else { return false }
        }
        return true
    }
}

extension _ConditionalContent where TrueContent: View, FalseContent: View {
    public func _isEquivalent(to other: _ConditionalContent<TrueContent, FalseContent>) -> Bool {
        switch (storage, other.storage) {
        case (.trueContent(let a), .trueContent(let b)):
            return _areEquivalent(a, b)
        case (.falseContent(let a), .falseContent(let b)):
            return _areEquivalent(a, b)
        default:
            return false
        }
    }
}

extension Optional where Wrapped: View {
    @MainActor
    public func _isEquivalent(to other: Wrapped?) -> Bool {
        switch (self, other) {
        case (.some(let a), .some(let b)):
            return _areEquivalent(a, b)
        case (.none, .none):
            return true
        default:
            return false
        }
    }
}

// The rest carry closures, so there is nothing to compare.

extension AnyView {
    public func _isEquivalent(to other: AnyView) -> Bool { false }
}

extension ForEach {
    public func _isEquivalent(to other: ForEach<Data, ID, Content>) -> Bool { false }
}
