//
//  FocusState.swift
//  NucleantUI
//
//  `@FocusState` — where the keys are, as a value a view can read and set.
//  The views it describes are marked with `.focused` (FocusModifiers.swift);
//  the host keeps the value in step with the view that has the keys, and
//  moves the keys when the value is set.
//

/// A value that says which view has the keys, and moves them when set.
///
/// ```swift
/// enum Field { case name, email }
///
/// @View
/// struct SignUp {
///     @State private var name = ""
///     @State private var email = ""
///     @FocusState private var focused: Field?
///
///     var body: some View {
///         VStack {
///             TextField("Name", text: $name)
///                 .focused($focused, equals: .name)
///                 .onSubmit { focused = .email }
///             TextField("Email", text: $email)
///                 .focused($focused, equals: .email)
///         }
///         .onAppear { focused = .name }
///     }
/// }
/// ```
///
/// A `Bool` focus state marks one view; an optional one marks several,
/// each with its own value, and is `nil` while none of them has the keys.
@propertyWrapper
@MainActor
public struct FocusState<Value: Hashable>: DynamicProperty {

    /// The slot, once the view is bound.
    private var storage: StateStorage<Value>?

    /// What the value is while no marked view has the keys.
    private let empty: Value

    public init() where Value == Bool {
        empty = false
    }

    public init<T: Hashable>() where Value == T? {
        empty = nil
    }

    private var storageOrFail: StateStorage<Value> {
        guard let storage else {
            preconditionFailure(
                "@FocusState used before the view was built. Reading or writing focus "
                + "outside of `body` and the actions it creates is not supported."
            )
        }
        return storage
    }

    /// The marked view that has the keys — `true`, or its value — or the
    /// empty value. Setting it moves the keys there; setting the empty
    /// value takes them away.
    public var wrappedValue: Value {
        get { storageOrFail.read() }
        nonmutating set { storageOrFail.set(newValue) }
    }

    /// `$focused` — what `.focused` takes.
    public var projectedValue: Binding {
        Binding(storage: storageOrFail, empty: empty)
    }

    public mutating func _bind(to context: BindingContext) {
        let empty = self.empty
        storage = context.slot(initialValue: { empty })
    }

    /// A focus state handed to `.focused`, or down to a view below as
    /// `@FocusState.Binding`.
    @propertyWrapper
    @MainActor
    public struct Binding {
        let storage: StateStorage<Value>
        let empty: Value

        public var wrappedValue: Value {
            get { storage.read() }
            nonmutating set { storage.set(newValue) }
        }

        public var projectedValue: Binding { self }

        /// Which focus state this is — the marks of one state are kept
        /// in step together.
        var identity: ObjectIdentifier { ObjectIdentifier(storage) }

        /// The value with no read recorded — the host, not a view, asks.
        func peek() -> Value { storage.peek() }

        var version: UInt32 { storage.version }
    }
}
