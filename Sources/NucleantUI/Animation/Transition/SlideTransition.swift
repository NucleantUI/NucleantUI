//
//  SlideTransition.swift
//  NucleantUI
//

/// A transition that inserts by moving in from the leading edge, and
/// removes by moving out towards the trailing edge.
///
/// - SeeAlso: `MoveTransition`
@MainActor @preconcurrency
public struct SlideTransition: Transition, Equatable {

    public init() {}

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: SlideTransition.Content, phase: TransitionPhase) -> some View {
        content.moveEffect(towards: Self.edge(in: phase))
    }

    /// Where the view is drawn from, and to: the leading edge on the way
    /// in, the trailing on the way out.
    private static func edge(in phase: TransitionPhase) -> Edge? {
        switch phase {
        case .willAppear: return .leading
        case .identity: return nil
        case .didDisappear: return .trailing
        }
    }
}

extension SlideTransition: BuiltinTransition {
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        let xy = MoveEffectContent.fraction(towards: Self.edge(in: phase))
        return [.move(x: xy[0], y: xy[1])]
    }
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == SlideTransition {

    /// A transition that inserts by moving in from the leading edge, and
    /// removes by moving out towards the trailing edge.
    ///
    /// - SeeAlso: `AnyTransition.move(edge:)`
    public static var slide: SlideTransition {
        SlideTransition()
    }
}
