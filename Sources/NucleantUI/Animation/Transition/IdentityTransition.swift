//
//  IdentityTransition.swift
//  NucleantUI
//

/// A transition that returns the input view, unmodified, as the output
/// view.
@MainActor @preconcurrency
public struct IdentityTransition: Transition, Equatable {

    public init() {}

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: IdentityTransition.Content, phase: TransitionPhase) -> IdentityTransition.Content {
        content
    }

    /// Returns the properties this transition type has.
    ///
    /// Defaults to `TransitionProperties()`.
    public static let properties = TransitionProperties(hasMotion: false)
}

extension IdentityTransition: BuiltinTransition {
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == IdentityTransition {

    /// A transition that returns the input view, unmodified, as the output
    /// view.
    public static var identity: IdentityTransition {
        IdentityTransition()
    }
}
