//
//  ScaleTransition.swift
//  NucleantUI
//

/// Returns a transition that scales the view.
@MainActor @preconcurrency
public struct ScaleTransition: Transition, Equatable {

    /// The amount to scale the view by.
    public var scale: Double

    /// The anchor point to scale the view around.
    public var anchor: UnitPoint

    /// Creates a transition that scales the view by the specified amount.
    public init(_ scale: Double, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: ScaleTransition.Content, phase: TransitionPhase) -> some View {
        content.scaleEffect(phase.isIdentity ? 1 : scale, anchor: anchor)
    }
}

extension ScaleTransition: BuiltinTransition {
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        let factor = phase.isIdentity ? 1 : scale
        return [.scale(x: factor, y: factor, anchor: anchor)]
    }
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == ScaleTransition {

    /// Returns a transition that scales the view.
    public static var scale: ScaleTransition {
        ScaleTransition(0)
    }

    /// Returns a transition that scales the view by the specified amount.
    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> Self {
        ScaleTransition(scale, anchor: anchor)
    }
}
