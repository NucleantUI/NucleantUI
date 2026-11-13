//
//  Binding.swift
//  NucleantUI
//

/// A two-way reference to a value owned elsewhere — what `$state` produces and
/// what a child view takes when it needs to write back.
@propertyWrapper
@dynamicMemberLookup
@MainActor
public struct Binding<Value>: DynamicProperty {

    /// Where the value is read and written. Reads take the full key path of
    /// the *outermost* binding (`chain`), handed down unchanged so the slot
    /// at the root records the read at that granularity; writes carry it
    /// down to the slot so it can dirty only the readers that overlap it.
    private let location: BindingLocation<Value>

    /// What this binding points at, when the framework can tell: the `@State`
    /// slot it was projected from, and the key paths walked since. Two
    /// bindings with the same source are the same input to a view, whatever
    /// their closures look like — see `ViewInput`. A binding built from raw
    /// closures has no source and never counts as equivalent.
    let source: BindingSource?

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.location = ClosureLocation(get: { _ in get() }, set: { newValue, _ in set(newValue) })
        self.source = nil
    }

    /// A binding with closures of its own over another binding's source — a
    /// conversion of the value that stays the same input as the binding it
    /// converts.
    init(
        source: BindingSource?,
        get: @escaping ([AnyKeyPath]?) -> Value,
        set: @escaping (Value, [AnyKeyPath]) -> Void
    ) {
        self.location = ClosureLocation(get: get, set: set)
        self.source = source
    }

    init(source: BindingSource?, location: BindingLocation<Value>) {
        self.location = location
        self.source = source
    }

    /// A binding that ignores writes — for previews and constant inputs.
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    private var chain: [AnyKeyPath] { source?.keyPaths ?? [] }

    public var wrappedValue: Value {
        get { location.get(chain) }
        nonmutating set { location.set(newValue, chain) }
    }

    /// `$binding` on a binding is the binding itself, so it can be forwarded
    /// down another level.
    public var projectedValue: Binding<Value> { self }

    /// A binding to one property of the bound value — `$model.name`.
    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Binding<Subject> {
        Binding<Subject>(source: source?.appending(keyPath), location: location.projecting(keyPath))
    }

    /// Nothing to wire up — a binding carries its own location.
    public func _bind(to context: BindingContext) {}
}

extension Binding: @preconcurrency Equatable where Value: Equatable {
    public static func == (lhs: Binding<Value>, rhs: Binding<Value>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

/// The state slot a binding was projected from plus the key paths applied to
/// it since — `$tracks[3].level` is `(tracks slot, [\.[3], \.level])`.
struct BindingSource: Hashable {
    let root: ObjectIdentifier
    let keyPaths: [AnyKeyPath]

    func appending(_ keyPath: AnyKeyPath) -> BindingSource {
        BindingSource(root: root, keyPaths: keyPaths + [keyPath])
    }
}

/// Where a binding reads and writes its value: `@State`'s slot, through the
/// key paths walked from it (`StateLocation`), or a pair of closures
/// (`ClosureLocation`).
@MainActor
class BindingLocation<Value> {

    /// The value. `chain` is the outermost binding's, for the slot to record
    /// the read; `nil` reads without recording, for a write's
    /// read-modify-write.
    func get(_ chain: [AnyKeyPath]?) -> Value {
        fatalError("each location overrides it")
    }

    func set(_ newValue: Value, _ chain: [AnyKeyPath]) {
        fatalError("each location overrides it")
    }

    /// The location of one property of the value.
    func projecting<Subject>(_ keyPath: WritableKeyPath<Value, Subject>) -> BindingLocation<Subject> {
        fatalError("each location overrides it")
    }
}

/// A value reached through a pair of closures. A property of it is read
/// out of the whole value, and written by writing the whole value back.
final class ClosureLocation<Value>: BindingLocation<Value> {
    private let read: ([AnyKeyPath]?) -> Value
    private let write: (Value, [AnyKeyPath]) -> Void

    init(get: @escaping ([AnyKeyPath]?) -> Value, set: @escaping (Value, [AnyKeyPath]) -> Void) {
        self.read = get
        self.write = set
    }

    override func get(_ chain: [AnyKeyPath]?) -> Value {
        read(chain)
    }

    override func set(_ newValue: Value, _ chain: [AnyKeyPath]) {
        write(newValue, chain)
    }

    override func projecting<Subject>(_ keyPath: WritableKeyPath<Value, Subject>) -> BindingLocation<Subject> {
        ClosureLocation<Subject>(
            get: { chain in self.read(chain)[keyPath: keyPath] },
            set: { newValue, chain in
                var copy = self.read(nil)
                copy[keyPath: keyPath] = newValue
                self.write(copy, chain)
            }
        )
    }
}

/// A part of an `@State` value: the slot, and the key path from its value
/// to the part, every projection since the slot in one. A read takes the
/// part where it lies; a write compares and writes only the part
/// (`StateStorage.set(_:at:via:)`). Another projection adds to the key
/// path, not another level of closures.
final class StateLocation<Root, Value>: BindingLocation<Value> {
    /// The state's holder, which has the slot once its view is built: a
    /// binding made before that finds it when it is used.
    private let holder: _StateProperty<Root>.Holder
    private let path: WritableKeyPath<Root, Value>

    init(holder: _StateProperty<Root>.Holder, path: WritableKeyPath<Root, Value>) {
        self.holder = holder
        self.path = path
    }

    override func get(_ chain: [AnyKeyPath]?) -> Value {
        guard let storage = holder.storage else {
            preconditionFailure("@State projected before the view was built.")
        }
        if let chain { storage.noteRead(via: chain) }
        return storage.value[keyPath: path]
    }

    override func set(_ newValue: Value, _ chain: [AnyKeyPath]) {
        holder.storage?.set(newValue, at: path, via: chain)
    }

    override func projecting<Subject>(_ keyPath: WritableKeyPath<Value, Subject>) -> BindingLocation<Subject> {
        StateLocation<Root, Subject>(holder: holder, path: path.appending(path: keyPath))
    }
}

/// An `@State` value as a whole.
final class StateRootLocation<Value>: BindingLocation<Value> {
    private let holder: _StateProperty<Value>.Holder

    init(holder: _StateProperty<Value>.Holder) {
        self.holder = holder
    }

    override func get(_ chain: [AnyKeyPath]?) -> Value {
        guard let storage = holder.storage else {
            preconditionFailure("@State projected before the view was built.")
        }
        return chain.map { storage.read(via: $0) } ?? storage.peek()
    }

    // Through the same setter as `wrappedValue`, so a binding write can't
    // bump the version without invalidating, or vice versa.
    override func set(_ newValue: Value, _ chain: [AnyKeyPath]) {
        holder.storage?.set(newValue, via: chain)
    }

    override func projecting<Subject>(_ keyPath: WritableKeyPath<Value, Subject>) -> BindingLocation<Subject> {
        StateLocation<Value, Subject>(holder: holder, path: keyPath)
    }
}
