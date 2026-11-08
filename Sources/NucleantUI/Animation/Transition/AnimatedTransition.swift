//
//  AnimatedTransition.swift
//  NucleantUI
//

/// What `animation(_:)` makes: `base`, its changes of phase animated with
/// `animation` whatever the change around them animates with. The
/// override is `.animation(_:value:)` on the phase — it acts only when the
/// phase changes, so the view, once arrived, animates with whatever
/// animates it.
@MainActor
struct AnimatedTransition<Base: Transition>: Transition {
    let base: Base
    let animation: Animation?

    func body(content: Content, phase: TransitionPhase) -> some View {
        AppliedTransition(transition: base, phase: phase, content: content)
            .animation(animation, value: phase)
    }

    static var properties: TransitionProperties {
        Base.properties
    }
}

extension AnimatedTransition: ViewInput {
    func _isEquivalent(to other: AnimatedTransition<Base>) -> Bool {
        animation == other.animation && transitionsAreEquivalent(base, other.base)
    }
}

extension AnimatedTransition: BuiltinTransition {
    static var identityLeavesViewUnchanged: Bool { Base.leavesViewUnchangedAtIdentity }
    /// It brings its own animation both ways: arriving and leaving run
    /// even when the change that caused them did not animate.
    static var animatesArrival: Bool { true }
    static var animatesRemoval: Bool { true }
}
