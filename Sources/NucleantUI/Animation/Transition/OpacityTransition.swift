//
//  OpacityTransition.swift
//  NucleantUI
//

/// A transition from transparent to opaque on insertion, and from opaque to
/// transparent on removal.
@MainActor @preconcurrency
public struct OpacityTransition: Transition, Equatable {

    public init() {}

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: OpacityTransition.Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0)
    }

    /// Returns the properties this transition type has.
    ///
    /// Defaults to `TransitionProperties()`.
    public static let properties = TransitionProperties(hasMotion: false)
}

extension OpacityTransition: BuiltinTransition {
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        [.opacity(phase.isIdentity ? 1 : 0)]
    }
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == OpacityTransition {

    /// A transition from transparent to opaque on insertion, and from opaque
    /// to transparent on removal.
    public static var opacity: OpacityTransition {
        OpacityTransition()
    }
}
