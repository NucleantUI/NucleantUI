//
//  DynamicProperty.swift
//  NucleantUI
//

/// A property of a view that the framework has to wire up before the view's
/// `body` runs — `@State` needs its storage, `@Environment` needs the current
/// environment.
///
/// The builder binds the copy of the view it is about to build, in place,
/// and runs `body` on that copy: a wrapper keeps what it was bound to in its
/// own fields, and the copies `body` makes — the closures it hands out, the
/// projections it passes down — are made from the bound one. A view value
/// that is made and then found equivalent to the one standing is never
/// bound, and costs its wrappers nothing.
@MainActor
public protocol DynamicProperty {
    mutating func _bind(to context: BindingContext)
}

/// Everything a dynamic property may need at bind time.
@MainActor
public struct BindingContext {
    /// Where the view stands: its state is held there.
    let position: ViewPosition
    /// Which of the view's stored properties is being bound.
    let index: Int
    /// The view being bound — state is only ever its own.
    let owner: ViewIdentity
    /// Its path: the subtree a write to its state invalidates.
    let ownerPath: [Int]
    let environment: EnvironmentValues

    init(position: ViewPosition, index: Int, owner: ViewIdentity, ownerPath: [Int], environment: EnvironmentValues) {
        self.position = position
        self.index = index
        self.owner = owner
        self.ownerPath = ownerPath
        self.environment = environment
    }

    /// The state slot of the property being bound, made from
    /// `initialValue` the first time its view is built here.
    func slot<Value>(initialValue: () -> Value) -> StateStorage<Value> {
        position.stateSlot(index, of: owner, ownerPath: ownerPath, initialValue: initialValue)
    }
}

/// Hands each dynamic property of one view its `BindingContext`.
///
/// `@View`'s generated `_bindDynamicProperties` calls `bind` once per wrapped
/// property, with the property's ordinal among the struct's stored
/// properties, so a view's state slots follow its declaration.
@MainActor
public struct DynamicPropertyBinder {
    let position: ViewPosition
    let environment: EnvironmentValues
    let path: [Int]
    let owner: ViewIdentity

    public func bind<P: DynamicProperty>(_ property: inout P, index: Int) {
        property._bind(to: BindingContext(
            position: position,
            index: index,
            owner: owner,
            ownerPath: path,
            environment: environment
        ))
    }

    /// A wrapped property that is not a dynamic property — a user's own
    /// wrapper — needs nothing from the framework. The overload exists so the
    /// macro can emit a `bind` for every wrapper without knowing which are.
    public func bind<P>(_ property: inout P, index: Int) {}
}

/// What an effect a view attached is filed under — its `onAppear` mark, an
/// `onChange`'s last value, its `onDisappear` action: the structural
/// position of the view, plus which effect it is.
///
/// Structural — not object — identity, because views are values. The same
/// position in the same shape of tree is the same view across rebuilds, which
/// is exactly SwiftUI's rule.
public struct StateKey: Hashable, Sendable {
    /// The structural path of the view that attached the effect.
    let path: [Int]
    let propertyIndex: Int
    /// The kind of effect, as a marker type. Only ever compared, never
    /// printed, so the identity of the type is enough.
    let viewType: ObjectIdentifier
    /// The call site (`ViewID.unknown` when there is none).
    let viewID: ViewID

    init(path: [Int], propertyIndex: Int, viewType: ObjectIdentifier, viewID: ViewID = .unknown) {
        self.path = path
        self.propertyIndex = propertyIndex
        self.viewType = viewType
        self.viewID = viewID
    }
}
