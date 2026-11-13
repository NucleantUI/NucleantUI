//
//  Namespace.swift
//  NucleantUI
//
//  `@Namespace` — an identity for a family of views to be matched by, owned
//  by the view that declares it: the same namespace for as long as that
//  view keeps its identity, and a new one for a new view.
//

/// A namespace defined by the persistent identity of the view that holds
/// the property.
///
/// ```swift
/// @View
/// struct Gallery {
///     @Namespace private var zoom
///
///     var body: some View {
///         NavigationStack {
///             ForEach(photos) { photo in
///                 NavigationLink(value: photo) {
///                     Thumbnail(photo)
///                         .matchedTransitionSource(id: photo.id, in: zoom)
///                 }
///             }
///             .navigationDestination(for: Photo.self) { photo in
///                 PhotoDetail(photo)
///                     .navigationTransition(.zoom(sourceID: photo.id, in: zoom))
///             }
///         }
///     }
/// }
/// ```
@propertyWrapper
@MainActor
public struct Namespace: DynamicProperty, Sendable {

    /// A namespace made by an `@Namespace` property.
    public struct ID: Hashable, Sendable {
        let value: Int

        /// A namespace no other has: one for each `@Namespace` the first
        /// time its view is built.
        @MainActor
        static func next() -> ID {
            nextValue += 1
            return ID(value: nextValue)
        }

        @MainActor private static var nextValue = 0
    }

    /// The slot, once the view is bound.
    private var storage: StateStorage<ID>?

    public init() {}

    public var wrappedValue: ID {
        guard let storage else {
            preconditionFailure(
                "@Namespace read before the view was built. Reading it outside of `body` "
                + "and the actions it creates is not supported."
            )
        }
        return storage.peek()
    }

    public mutating func _bind(to context: BindingContext) {
        storage = context.store.slot(for: context.key, initialValue: { ID.next() })
    }
}
