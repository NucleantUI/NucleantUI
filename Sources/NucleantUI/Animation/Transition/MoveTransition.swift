//
//  MoveTransition.swift
//  NucleantUI
//
//  `MoveTransition`, and the effect it — and `SlideTransition` and
//  `PushTransition` — moves a view with: the view drawn its own width or
//  height towards an edge. The distance is a fraction of the view's size,
//  so it is the fraction that animates, and the size is read where the
//  view is placed: a view that changes size while it moves still ends up
//  exactly one of its own widths away. A render transform, like `.offset`:
//  nothing moves in layout, and what is under the view is hit through it.
//

/// Returns a transition that moves the view away, towards the specified
/// edge of the view.
@MainActor @preconcurrency
public struct MoveTransition: Transition, Equatable {

    /// The edge to move the view towards.
    public var edge: Edge

    /// Creates a transition that moves the view away, towards the specified
    /// edge of the view.
    public init(edge: Edge) {
        self.edge = edge
    }

    /// Gets the current body of the caller.
    ///
    /// `content` is a proxy for the view that will have the modifier
    /// represented by `Self` applied to it.
    public func body(content: MoveTransition.Content, phase: TransitionPhase) -> some View {
        content.moveEffect(towards: phase.isIdentity ? nil : edge)
    }
}

extension MoveTransition: BuiltinTransition {
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        let xy = MoveEffectContent.fraction(towards: phase.isIdentity ? nil : edge)
        return [.move(x: xy[0], y: xy[1])]
    }
    static var identityLeavesViewUnchanged: Bool { true }
    static var animatesArrival: Bool { false }
    static var animatesRemoval: Bool { false }
}

extension Transition where Self == MoveTransition {

    /// Returns a transition that moves the view away, towards the specified
    /// edge of the view.
    public static func move(edge: Edge) -> Self {
        MoveTransition(edge: edge)
    }
}

// MARK: - The move

extension View {
    /// This view drawn one of its own widths or heights towards `edge`, or
    /// where it is for `nil`. Animates its own amount.
    func moveEffect(towards edge: Edge?) -> some View {
        _ModifierView(content: self, key: ["moveEffect", edge] as [AnyHashable]) { context in
            MoveEffectContent(fraction: context.animatedValue(.move, MoveEffectContent.fraction(towards: edge)))
        }
    }
}

/// How far a view is drawn from where it is placed, as a fraction of its
/// own size along each axis — (-1, 0) is one width to the left.
struct MoveEffectContent: NodeContent {
    /// `[x, y]`, animated.
    let fraction: AnimatedVector

    static func fraction(towards edge: Edge?) -> [Double] {
        switch edge {
        case nil: return [0, 0]
        case .leading: return [-1, 0]
        case .trailing: return [1, 0]
        case .top: return [0, -1]
        case .bottom: return [0, 1]
        }
    }

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let xy = fraction.current()
        var inner = context
        let dx = xy[0] * rect.width
        let dy = xy[1] * rect.height
        if dx != 0 || dy != 0 {
            inner.transform = context.transform.concatenating(.translation(x: dx, y: dy))
        }
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}
