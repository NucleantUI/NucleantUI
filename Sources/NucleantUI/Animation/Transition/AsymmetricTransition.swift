//
//  AsymmetricTransition.swift
//  NucleantUI
//

/// A composite `Transition` that uses a different transition for
/// insertion versus removal.
///
/// Both are applied to the view the whole time, each in its own phase: the
/// insertion transition is in `willAppear` only while the view arrives,
/// the removal transition in `didDisappear` only while it leaves, and both
/// in `identity` otherwise. A view removed while still arriving finishes
/// its arrival as it leaves.
@MainActor @preconcurrency
public struct AsymmetricTransition<Insertion: Transition, Removal: Transition>: Transition {

    /// The `Transition` defining the insertion phase of `self`.
    public var insertion: Insertion

    /// The `Transition` defining the removal phase of `self`.
    public var removal: Removal

    /// Creates a composite `Transition` that uses a different transition for
    /// insertion versus removal.
    public init(insertion: Insertion, removal: Removal) {
        self.insertion = insertion
        self.removal = removal
    }

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: AsymmetricTransition<Insertion, Removal>.Content, phase: TransitionPhase) -> some View {
        AppliedTransition(
            transition: removal,
            phase: phase == .didDisappear ? .didDisappear : .identity,
            content: AppliedTransition(
                transition: insertion,
                phase: phase == .willAppear ? .willAppear : .identity,
                content: content
            )
        )
    }

    /// Returns the properties this transition type has: motion if either
    /// half has it.
    public static var properties: TransitionProperties {
        TransitionProperties(hasMotion: Insertion.properties.hasMotion || Removal.properties.hasMotion)
    }
}

extension AsymmetricTransition: ViewInput {
    /// Equivalent halves: a view whose transition this is need not be
    /// built again for it.
    public func _isEquivalent(to other: AsymmetricTransition<Insertion, Removal>) -> Bool {
        transitionsAreEquivalent(insertion, other.insertion) && transitionsAreEquivalent(removal, other.removal)
    }
}

extension AsymmetricTransition: BuiltinTransition {
    static var identityLeavesViewUnchanged: Bool {
        Insertion.leavesViewUnchangedAtIdentity && Removal.leavesViewUnchangedAtIdentity
    }
    /// The arrival moves the insertion half only; leaving, and coming back
    /// while leaving, the removal half only.
    static var animatesArrival: Bool { Insertion.hasAnimatedArrival }
    static var animatesRemoval: Bool { Removal.hasAnimatedRemoval }
}
