//
//  PushTransition.swift
//  NucleantUI
//

/// A transition that when added to a view will animate the view's insertion
/// by moving it in from the specified edge while fading it in, and animate
/// its removal by moving it out towards the opposite edge and fading it out.
@MainActor @preconcurrency
public struct PushTransition: Transition, Equatable {

    /// The edge from which the view will be animated in.
    public var edge: Edge

    /// Creates a transition that animates a view by moving and fading it.
    public init(edge: Edge) {
        self.edge = edge
    }

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: PushTransition.Content, phase: TransitionPhase) -> some View {
        content
            .moveEffect(towards: edge(in: phase))
            .opacity(phase.isIdentity ? 1 : 0)
    }

    /// In from `edge`, out towards the opposite one.
    private func edge(in phase: TransitionPhase) -> Edge? {
        switch phase {
        case .willAppear: return edge
        case .identity: return nil
        case .didDisappear: return edge.opposite
        }
    }
}

extension PushTransition: BuiltinTransition {
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == PushTransition {

    /// Creates a transition that when added to a view will animate the
    /// view's insertion by moving it in from the specified edge while
    /// fading it in, and animate its removal by moving it out towards
    /// the opposite edge and fading it out.
    ///
    /// - Parameters:
    ///   - edge: the edge from which the view will be animated in.
    ///
    /// - Returns: A transition that animates a view by moving and
    ///   fading it.
    public static func push(from edge: Edge) -> Self {
        PushTransition(edge: edge)
    }
}

extension Edge {
    /// The edge across from this one.
    var opposite: Edge {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }
}
