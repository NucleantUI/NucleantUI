//
//  AnyTransition.swift
//  NucleantUI
//
//  The type-erased transition. An `AnyTransition` holds one `Transition`
//  of any type, boxed: an abstract `AnyTransitionBox` the containers talk
//  to, and a `TransitionBox<T>` that knows the type and builds its body.
//  Everything an `AnyTransition` can do is a transition underneath —
//  `.opacity` is an `OpacityTransition`, `.asymmetric` an
//  `AsymmetricTransition` of the two it was given, `combined(with:)` and
//  `animation(_:)` the transitions `Transition`'s own methods make. The two
//  erased sides of a composition each know their own type only, so each
//  hands its type to the other's box (`combined(after:)`,
//  `asymmetric(insertion:)`), and the box that ends up knowing both makes
//  the composed transition — still a concrete type, erased once.
//

/// A type-erased transition.
///
/// - See Also: ``Transition``
@MainActor
public struct AnyTransition {

    let box: AnyTransitionBox

    /// Create an instance that type-erases `transition`.
    public init<T: Transition>(_ transition: T) {
        box = TransitionBox(transition)
    }

    init(box: AnyTransitionBox) {
        self.box = box
    }
}

extension AnyTransition: ViewInput {
    /// The same transition: one box, or two holding equivalent transitions
    /// of the same type.
    public func _isEquivalent(to other: AnyTransition) -> Bool {
        box === other.box || box.isEquivalent(to: other.box)
    }
}

extension AnyTransition {

    /// Returns a transition defined between an active modifier and an
    /// identity modifier.
    public static func modifier<E: ViewModifier>(active: E, identity: E) -> AnyTransition {
        AnyTransition(ModifierTransition(active: active, identity: identity))
    }
}

extension AnyTransition {

    public static func offset(_ offset: Size) -> AnyTransition {
        AnyTransition(OffsetTransition(offset))
    }

    public static func offset(x: Double = 0, y: Double = 0) -> AnyTransition {
        AnyTransition(OffsetTransition(Size(width: x, height: y)))
    }
}

extension AnyTransition {

    /// Returns a transition that moves the view away, towards the specified
    /// edge of the view.
    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(MoveTransition(edge: edge))
    }
}

extension AnyTransition {

    /// A transition from transparent to opaque on insertion, and from opaque
    /// to transparent on removal.
    public static let opacity = AnyTransition(OpacityTransition())
}

extension AnyTransition {

    /// Provides a composite transition that uses a different transition for
    /// insertion versus removal.
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(box: insertion.box.asymmetric(removal: removal.box))
    }
}

extension AnyTransition {

    /// A transition that inserts by moving in from the leading edge, and
    /// removes by moving out towards the trailing edge.
    ///
    /// - SeeAlso: `AnyTransition.move(edge:)`
    public static var slide: AnyTransition {
        AnyTransition(SlideTransition())
    }
}

extension AnyTransition {

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
    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition(PushTransition(edge: edge))
    }
}

extension AnyTransition {

    /// Attaches an animation to this transition.
    ///
    /// The view arrives and leaves under `animation`, even when the change
    /// that inserted or removed it is not animated.
    public func animation(_ animation: Animation?) -> AnyTransition {
        AnyTransition(box: box.animated(animation))
    }
}

extension AnyTransition {

    /// Combines this transition with another, returning a new transition
    /// that is the result of both transitions being applied.
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(box: box.combined(with: other.box))
    }
}

extension AnyTransition {

    /// A transition that returns the input view, unmodified, as the output
    /// view.
    public static let identity = AnyTransition(IdentityTransition())
}

extension AnyTransition {

    /// Returns a transition that scales the view.
    public static var scale: AnyTransition {
        AnyTransition(ScaleTransition(0))
    }

    /// Returns a transition that scales the view by the specified amount.
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(ScaleTransition(scale, anchor: anchor))
    }
}

/// Whether two transitions of one type build the same body: equivalent as
/// view inputs — or, for a type that stores nothing, always: it has only
/// the one value.
@MainActor
func transitionsAreEquivalent<T: Transition>(_ a: T, _ b: T) -> Bool {
    MemoryLayout<T>.size == 0 || _areEquivalent(a, b)
}

// MARK: - The box

/// What a container asks of a transition it holds erased. Every answer is
/// worked out once, when the box is made, from the type it holds.
@MainActor
class AnyTransitionBox {

    /// The body is the content itself (`IdentityTransition`): there is
    /// nothing to build, in any phase.
    let isIdentity: Bool

    /// The body changes nothing in `identity` — see `BuiltinTransition`.
    let leavesViewUnchangedAtIdentity: Bool

    /// The view arrives under an animation of the transition's own, even
    /// when the change inserting it does not animate.
    let animatesArrival: Bool

    /// The view leaves — or comes back while leaving — under an animation
    /// of the transition's own.
    let animatesRemoval: Bool

    init(isIdentity: Bool, leavesViewUnchangedAtIdentity: Bool, animatesArrival: Bool, animatesRemoval: Bool) {
        self.isIdentity = isIdentity
        self.leavesViewUnchangedAtIdentity = leavesViewUnchangedAtIdentity
        self.animatesArrival = animatesArrival
        self.animatesRemoval = animatesRemoval
    }

    /// Build the transition's body for `phase` at `context`'s path, its
    /// placeholder standing for `content`.
    func makeBody(phase: TransitionPhase, content: PlaceholderContent, context: inout BuildContext) -> ViewNode {
        fatalError("AnyTransitionBox is abstract")
    }

    /// Whether `other` holds a transition of the same type, equivalent to
    /// this one's.
    func isEquivalent(to other: AnyTransitionBox) -> Bool {
        fatalError("AnyTransitionBox is abstract")
    }

    /// What the held transition draws in `phase`, when it is a built-in
    /// that can say — a slot then draws it without building the body.
    func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        fatalError("AnyTransitionBox is abstract")
    }

    /// The held transition with `animation` attached.
    func animated(_ animation: Animation?) -> AnyTransitionBox {
        fatalError("AnyTransitionBox is abstract")
    }

    /// The held transition combined with `other`'s, `other`'s applied over.
    func combined(with other: AnyTransitionBox) -> AnyTransitionBox {
        fatalError("AnyTransitionBox is abstract")
    }

    /// `first` combined with the held transition — the other half of
    /// `combined(with:)`, asked of the box whose type comes second.
    func combined<First: Transition>(after first: First) -> AnyTransitionBox {
        fatalError("AnyTransitionBox is abstract")
    }

    /// The held transition for insertion, `removal`'s for removal.
    func asymmetric(removal: AnyTransitionBox) -> AnyTransitionBox {
        fatalError("AnyTransitionBox is abstract")
    }

    /// `insertion` for insertion, the held transition for removal — the
    /// other half of `asymmetric(removal:)`.
    func asymmetric<Insertion: Transition>(insertion: Insertion) -> AnyTransitionBox {
        fatalError("AnyTransitionBox is abstract")
    }
}

/// The box around a transition of type `T`.
@MainActor
final class TransitionBox<T: Transition>: AnyTransitionBox {
    let base: T

    init(_ base: T) {
        self.base = base
        super.init(
            isIdentity: T.Body.self == PlaceholderContentView<T>.self,
            leavesViewUnchangedAtIdentity: T.leavesViewUnchangedAtIdentity,
            animatesArrival: T.hasAnimatedArrival,
            animatesRemoval: T.hasAnimatedRemoval
        )
    }

    override func makeBody(phase: TransitionPhase, content: PlaceholderContent, context: inout BuildContext) -> ViewNode {
        let body = base.body(content: PlaceholderContentView<T>(source: content), phase: phase)
        return buildNode(body, &context)
    }

    override func effects(in phase: TransitionPhase) -> [TransitionEffect]? {
        base.builtinEffects(in: phase)
    }

    override func isEquivalent(to other: AnyTransitionBox) -> Bool {
        guard let other = other as? TransitionBox<T> else { return false }
        return transitionsAreEquivalent(base, other.base)
    }

    override func animated(_ animation: Animation?) -> AnyTransitionBox {
        TransitionBox<AnimatedTransition<T>>(AnimatedTransition(base: base, animation: animation))
    }

    override func combined(with other: AnyTransitionBox) -> AnyTransitionBox {
        other.combined(after: base)
    }

    override func combined<First: Transition>(after first: First) -> AnyTransitionBox {
        TransitionBox<CombinedTransition<First, T>>(CombinedTransition(first: first, second: base))
    }

    override func asymmetric(removal: AnyTransitionBox) -> AnyTransitionBox {
        removal.asymmetric(insertion: base)
    }

    override func asymmetric<Insertion: Transition>(insertion: Insertion) -> AnyTransitionBox {
        TransitionBox<AsymmetricTransition<Insertion, T>>(AsymmetricTransition(insertion: insertion, removal: base))
    }
}
