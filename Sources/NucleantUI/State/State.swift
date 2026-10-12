//
//  State.swift
//  NucleantUI
//

/// A value the view owns and mutates, preserved across rebuilds.
///
/// ```swift
/// @View
/// struct Counter {
///     @State private var count = 0
///     var body: some View {
///         Button("tapped \(count)") { count += 1 }
///     }
/// }
/// ```
///
/// The initial value is evaluated once, when the view's state is first
/// created — not each time the struct is constructed. A parent rebuilding
/// makes a new `Counter` every time; `@State private var model = Model()`
/// still runs `Model()` only for the first one at that place in the tree,
/// and again only if that view goes away and a new one takes its place.
///
/// `@State` is a macro. `@State var count = 0` becomes:
///
/// * `private var _count = _StateProperty<Int>({ 0 })` — the storage,
///   holding the initial value as a closure;
/// * `get`/`nonmutating set` on `count` that go through `_count`, with any
///   `willSet`/`didSet` folded into the setter;
/// * `var $count: Binding<Int>` — the projection, as visible as `count`.
///
/// A property with no initial value (`@State var count: Int`) also gets an
/// `init` accessor, so an initializer can assign it: `self.count = start`.
/// For one *with* an initial value, `self.count = start` in an initializer
/// replaces that value — the first time; like the initial value itself, it
/// only counts when the state is created.
@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(_), prefixed(`$`))
public macro State() = #externalMacro(module: "NucleantUIMacros", type: "StateMacro")

/// Turns `$name`, declared with an initializer only to give it a type, into
/// `get { _name.projectedValue }`. Emitted by `@State` for a property whose
/// type is inferred: the projection's type can't be spelled, so the
/// initializer spells it and is never run.
@attached(accessor, names: named(get))
public macro _StateProjectedValue() = #externalMacro(module: "NucleantUIMacros", type: "StateProjectedValueMacro")

/// The storage behind an `@State` property — what the macro generates `_name`
/// as. Public only because that code is compiled in the module declaring the
/// view; written by hand, state is `@State`.
///
/// Not isolated itself, so a stored property's default value — written in a
/// nonisolated context — can make one; reading and writing it is main-actor
/// work, and the members that do are.
public struct _StateProperty<Value> {

    /// The one reference every copy of the storage shares. Binding fills in
    /// `storage`; `wrappedValue` reads through it.
    final class Holder {
        var storage: StateStorage<Value>?
        /// A value written before the view was built — `self.count = start`
        /// in an initializer. It takes the place of the initial value.
        var pending: Value?
    }

    enum Initial {
        case value(Value)
        /// Main actor: what it makes is usually an `@Observable` model,
        /// whose initializer is.
        case make(@MainActor () -> Value)
    }

    private let holder = Holder()
    private let initial: Initial

    /// Storage whose initial value is made when the state is first created,
    /// not now — for a property declared with one.
    public init(_ makeInitialValue: @escaping @MainActor () -> Value) {
        self.initial = .make(makeInitialValue)
    }

    /// Storage for a value the caller already has — a property declared
    /// without one, assigned in an initializer.
    public init(initialValue: Value) {
        self.initial = .value(initialValue)
    }

    @MainActor
    public var wrappedValue: Value {
        get {
            guard let storage = holder.storage else {
                if let pending = holder.pending {
                    return pending
                }
                preconditionFailure(
                    "@State read before the view was built. Reading state outside of "
                    + "`body` (in an initializer, say) is not supported."
                )
            }
            // `read()`, not `value`: a read inside a `body` is what registers
            // this view as depending on this state, and so what decides whether
            // a later write has to rebuild it.
            return storage.read()
        }
        nonmutating set {
            guard let storage = holder.storage else {
                holder.pending = newValue
                return
            }
            storage.set(newValue)
        }
    }

    /// `$state` — a two-way binding to this value.
    @MainActor
    public var projectedValue: Binding<Value> {
        let holder = self.holder
        return Binding(
            source: holder.storage.map { BindingSource(root: ObjectIdentifier($0), keyPaths: []) },
            get: { chain in
                guard let storage = holder.storage else {
                    preconditionFailure("@State projected before the view was built.")
                }
                return chain.map { storage.read(via: $0) } ?? storage.peek()
            },
            // Through the same setter as `wrappedValue`, so a binding write
            // can't bump the version without invalidating, or vice versa.
            set: { newValue, chain in holder.storage?.set(newValue, via: chain) }
        )
    }
}

extension _StateProperty: DynamicProperty {
    public func _bind(to context: BindingContext) {
        let holder = self.holder
        let initial = self.initial
        holder.storage = context.store.slot(for: context.key) {
            if let pending = holder.pending {
                return pending
            }
            switch initial {
            case .value(let value):
                return value
            case .make(let make):
                return make()
            }
        }
    }
}
