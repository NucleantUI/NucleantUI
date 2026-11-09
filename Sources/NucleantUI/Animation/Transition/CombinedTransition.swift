//
//  CombinedTransition.swift
//  NucleantUI
//

/// What `combined(with:)` makes: two transitions applied together, in the
/// same phase, `second` over `first`.
@MainActor
struct CombinedTransition<First: Transition, Second: Transition>: Transition {
    let first: First
    let second: Second

    func body(content: Content, phase: TransitionPhase) -> some View {
        AppliedTransition(
            transition: second,
            phase: phase,
            content: AppliedTransition(transition: first, phase: phase, content: content)
        )
    }

    /// Motion if either has it.
    static var properties: TransitionProperties {
        TransitionProperties(hasMotion: First.properties.hasMotion || Second.properties.hasMotion)
    }
}

extension CombinedTransition: ViewInput {
    func _isEquivalent(to other: CombinedTransition<First, Second>) -> Bool {
        transitionsAreEquivalent(first, other.first) && transitionsAreEquivalent(second, other.second)
    }
}

extension CombinedTransition: BuiltinTransition {
    /// `first` inside `second`, as the body has them — `nil` unless both
    /// can say.
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        guard let inner = first.builtinEffects(in: phase), let outer = second.builtinEffects(in: phase) else { return nil }
        return inner + outer
    }
    static var identityLeavesViewUnchanged: Bool {
        First.leavesViewUnchangedAtIdentity && Second.leavesViewUnchangedAtIdentity
    }
    static var animatesArrival: Bool { First.hasAnimatedArrival || Second.hasAnimatedArrival }
    static var animatesRemoval: Bool { First.hasAnimatedRemoval || Second.hasAnimatedRemoval }
}
