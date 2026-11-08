//
//  ModifierTransition.swift
//  NucleantUI
//

/// What `AnyTransition.modifier(active:identity:)` makes: `active` applied
/// to the view while it arrives and leaves, `identity` while it is shown.
/// The two are the same modifier type, so the view stays where it is in
/// the tree as one turns into the other — and the modifier's own animated
/// values (an `Animatable` one's data, an `.opacity` in its body) carry
/// the transition.
@MainActor
struct ModifierTransition<Modifier: ViewModifier>: Transition {
    let active: Modifier
    let identity: Modifier

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(phase.isIdentity ? identity : active)
    }
}

extension ModifierTransition: ViewInput {
    /// The same two modifiers — any two, of a modifier type that stores
    /// nothing.
    func _isEquivalent(to other: ModifierTransition<Modifier>) -> Bool {
        if MemoryLayout<Modifier>.size == 0 { return true }
        return _areEquivalent(active, other.active) && _areEquivalent(identity, other.identity)
    }
}
