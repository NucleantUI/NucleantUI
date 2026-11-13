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
    let isEquivalent = equivalenceWitness(for: T.self)
    return withUnsafePointer(to: a) { a in
        withUnsafePointer(to: b) { b in isEquivalent(UnsafeRawPointer(a), UnsafeRawPointer(b)) }
    }
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

// MARK: - Comparing by type

/// How two values of one type compare as view inputs, given pointers to
/// them. Chosen once per type by the same rules as `_dynamicallyEquivalent`
/// — `ViewInput`, then the same object, then `Equatable`, then the bytes of
/// plain data — so a value whose type is known is compared where it lies,
/// without being boxed as `Any`. A state slot takes its value type's when
/// it is made.
typealias EquivalenceWitness = @MainActor (UnsafeRawPointer, UnsafeRawPointer) -> Bool

/// The witness for values of type `T`, made the first time it is asked for.
@MainActor
func equivalenceWitness<T>(for type: T.Type) -> EquivalenceWitness {
    let id = ObjectIdentifier(type)
    if let known = witnesses[id] { return known }
    let made = makeWitness(type)
    witnesses[id] = made
    return made
}

@MainActor
private var witnesses: [ObjectIdentifier: EquivalenceWitness] = [:]

@MainActor
private func makeWitness<T>(_: T.Type) -> EquivalenceWitness {
    if let input = T.self as? any ViewInput.Type {
        return viewInputWitness(input)
    }
    if let optional = T.self as? any _OptionalValue.Type {
        return optionalWitness(optional)
    }
    if T.self is AnyClass {
        return { a, b in
            (a.assumingMemoryBound(to: T.self).pointee as AnyObject)
                === (b.assumingMemoryBound(to: T.self).pointee as AnyObject)
        }
    }
    if let equatable = T.self as? any Equatable.Type {
        return equatableWitness(equatable)
    }
    if _isPOD(T.self) {
        return { a, b in
            _plainBytesEqual(a.assumingMemoryBound(to: T.self).pointee, b.assumingMemoryBound(to: T.self).pointee)
        }
    }
    // Nothing the static type says. An existential's does not say what it
    // holds, which the values themselves do: asked as they are, as before.
    return { a, b in
        _dynamicallyEquivalent(a.assumingMemoryBound(to: T.self).pointee, b.assumingMemoryBound(to: T.self).pointee)
    }
}

/// Two optionals: both empty is the same, one empty is not, and two
/// values compare as their wrapped type's do — an object by identity, as
/// it is unwrapped.
@MainActor
private func optionalWitness<O: _OptionalValue>(_: O.Type) -> EquivalenceWitness {
    let isEquivalent = equivalenceWitness(for: O.Wrapped.self)
    return { a, b in
        switch (a.assumingMemoryBound(to: O.self).pointee._wrapped, b.assumingMemoryBound(to: O.self).pointee._wrapped) {
        case (nil, nil):
            return true
        case (let x?, let y?):
            return withUnsafePointer(to: x) { x in
                withUnsafePointer(to: y) { y in isEquivalent(UnsafeRawPointer(x), UnsafeRawPointer(y)) }
            }
        default:
            return false
        }
    }
}

/// `Optional`, for the comparing rules to see through.
protocol _OptionalValue {
    associatedtype Wrapped
    var _wrapped: Wrapped? { get }
}

extension Optional: _OptionalValue {
    var _wrapped: Wrapped? { self }
}

@MainActor
private func viewInputWitness<T: ViewInput>(_: T.Type) -> EquivalenceWitness {
    { a, b in a.assumingMemoryBound(to: T.self).pointee._isEquivalent(to: b.assumingMemoryBound(to: T.self).pointee) }
}

@MainActor
private func equatableWitness<T: Equatable>(_: T.Type) -> EquivalenceWitness {
    { a, b in _areEquivalent(a.assumingMemoryBound(to: T.self).pointee, b.assumingMemoryBound(to: T.self).pointee) }
}

/// The runtime answer for a value whose static type says nothing.
///
/// Order matters: `ViewInput` first, so a `Binding` compares by source and
/// not through its `Equatable` conformance (which reads the value — and two
/// bindings onto the same slot always read the same value, changed or not).
/// An `Optional` next, compared by what it wraps.
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
    if let value = value as? any _OptionalValue {
        return optionalComparator(value)
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
private func optionalComparator<O: _OptionalValue>(_: O) -> @MainActor (Any, Any) -> Bool {
    { a, b in
        switch ((a as! O)._wrapped, (b as! O)._wrapped) {
        case (nil, nil): return true
        case (let x?, let y?): return _dynamicallyEquivalent(x, y)
        default: return false
        }
    }
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
