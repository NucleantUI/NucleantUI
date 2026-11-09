//
//  OffsetTransition.swift
//  NucleantUI
//

/// Returns a transition that offset the view by the specified amount.
@MainActor @preconcurrency
public struct OffsetTransition: Transition, Equatable {

    /// The amount to offset the view by.
    public var offset: Size

    /// Creates a transition that offset the view by the specified amount.
    public init(_ offset: Size) {
        self.offset = offset
    }

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: OffsetTransition.Content, phase: TransitionPhase) -> some View {
        content.offset(phase.isIdentity ? .zero : offset)
    }
}

extension OffsetTransition: BuiltinTransition {
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        let amount = phase.isIdentity ? Size.zero : offset
        return [.offset(x: amount.width, y: amount.height)]
    }
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == OffsetTransition {

    /// Returns a transition that offset the view by the specified amount.
    public static func offset(_ offset: Size) -> Self {
        OffsetTransition(offset)
    }

    /// Returns a transition that offset the view by the specified x and y
    /// values.
    public static func offset(x: Double = 0, y: Double = 0) -> Self {
        OffsetTransition(Size(width: x, height: y))
    }
}
