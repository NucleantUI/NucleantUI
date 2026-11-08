//
//  Transition.swift
//  NucleantUI
//
//  How a view comes in and goes out — SwiftUI's `Transition`. A transition
//  is a body: the view it is attached to (`content`) with modifiers applied
//  for the stage it is at (`phase`). The containers that insert and remove
//  views — an `if`, a `switch`, a `ForEach`, a builder's `for` — build that
//  body around each child as it arrives and as it leaves, and move it from
//  phase to phase under the change's animation (TransitionSlots.swift). The
//  modifiers in the body animate their own values, and that is the
//  transition: nothing here knows what fading or sliding is.
//

/// A description of view changes to apply when a view is added to and
/// removed from the view hierarchy.
///
/// A transition is made by applying modifiers to `content`, the stand-in for
/// the view the transition is attached to. A symmetric transition sets its
/// modifiers from `phase.isIdentity`; an asymmetric one looks at the phase
/// itself. A transition should not change the identity of `content` — no
/// `.id`, `if` or `switch` around it — since the view it stands for would
/// start over each time it appeared or disappeared.
///
/// A transition that fades a view and turns it as it comes and goes:
///
/// ```swift
/// struct RotatingFadeTransition: Transition {
///     func body(content: Content, phase: TransitionPhase) -> some View {
///         content
///             .opacity(phase.isIdentity ? 1.0 : 0.0)
///             .rotationEffect(phase.rotation)
///     }
/// }
///
/// extension TransitionPhase {
///     fileprivate var rotation: Angle {
///         switch self {
///         case .willAppear: return .degrees(30)
///         case .identity: return .zero
///         case .didDisappear: return .degrees(-30)
///         }
///     }
/// }
/// ```
///
/// Attach it with `.transition(RotatingFadeTransition())`. Where values of
/// different transition types have to share one type — a model choosing a
/// transition per item — erase them into an ``AnyTransition``.
///
/// The body is built like any view's: every modifier works in it, an
/// `Animatable` `ViewModifier` of your own included, and so does a view
/// laid over the content. Its modifiers are on the view for as long as it
/// is shown, in `identity`, and should change nothing there.
@MainActor @preconcurrency
public protocol Transition {

    /// The type of view representing the body.
    associatedtype Body: View

    /// The view `content` stands for, as it should appear in `phase`.
    ///
    /// `content` is a proxy for the view that will have the transition
    /// represented by `Self` applied to it.
    @ViewBuilder @MainActor @preconcurrency
    func body(content: Content, phase: TransitionPhase) -> Body

    /// Returns the properties this transition type has.
    ///
    /// Defaults to `TransitionProperties()`.
    @MainActor @preconcurrency
    static var properties: TransitionProperties { get }

    /// The content view type passed to `body()`.
    typealias Content = PlaceholderContentView<Self>
}

extension Transition {

    /// Returns the properties this transition type has.
    ///
    /// Defaults to `TransitionProperties()`.
    public static var properties: TransitionProperties {
        TransitionProperties()
    }

    /// `content` with this transition applied as it is in `phase`: the
    /// body built around a view you hand it, rather than around one a
    /// container inserts or removes. What a transition made of other
    /// transitions puts in its own body.
    ///
    /// ```swift
    /// struct Unfold: Transition {
    ///     func body(content: Content, phase: TransitionPhase) -> some View {
    ///         MoveTransition(edge: .top)
    ///             .apply(content: content.scaleEffect(phase.isIdentity ? 1 : 0.6), phase: phase)
    ///     }
    /// }
    /// ```
    public func apply<V: View>(content: V, phase: TransitionPhase) -> some View {
        AppliedTransition(transition: self, phase: phase, content: content)
    }

    /// Attaches an animation to this transition.
    ///
    /// The view arrives and leaves under `animation`, whatever the change
    /// that inserted or removed it animates with — and it does so even when
    /// that change is not animated at all: a view with
    /// `.transition(.opacity.animation(.easeInOut))` fades in and out for
    /// a plain `isShown.toggle()`. `nil` makes it arrive and leave at once.
    public func animation(_ animation: Animation?) -> some Transition {
        AnimatedTransition(base: self, animation: animation)
    }

    /// This transition and `other`, both applied — `other` over this one.
    public func combined<T: Transition>(with other: T) -> some Transition {
        CombinedTransition(first: self, second: other)
    }
}

/// An indication of which the current stage of a transition.
///
/// A view appearing with a transition is first shown in `willAppear`, then
/// moved straight to `identity`; a view being removed moves from `identity`
/// to `didDisappear`. One removed while still appearing moves to
/// `didDisappear` from wherever it had got to; one brought back while still
/// disappearing moves back to `identity`.
///
/// In `identity` a transition should make no visual change: its modifiers
/// in that phase stay applied for as long as the view is visible. In
/// `willAppear` and `didDisappear` it applies the change that is animated
/// from and to. A transition that changes nothing animatable between the
/// phases does nothing.
@frozen
public enum TransitionPhase: Equatable, Hashable, Sendable, BitwiseCopyable {

    /// The transition is being applied to a view that is about to be
    /// inserted into the view hierarchy.
    ///
    /// In this phase, a transition should show the appearance that will be
    /// animated from to make the appearance transition.
    case willAppear

    /// The transition is being applied to a view that is in the view
    /// hierarchy.
    ///
    /// In this phase, a transition should show its steady state appearance,
    /// which will generally not make any visual change to the view.
    case identity

    /// The transition is being applied to a view that has been requested to
    /// be removed from the view hierarchy.
    ///
    /// In this phase, a transition should show the appearance that will be
    /// animated to to make the disappearance transition.
    case didDisappear

    /// A Boolean that indicates whether the transition should have an
    /// identity effect, i.e. not change the appearance of its view.
    ///
    /// This is true in the `identity` phase.
    public var isIdentity: Bool {
        self == .identity
    }
}

extension TransitionPhase {

    /// A value that can be used to multiply effects that are applied
    /// differently depending on the phase.
    ///
    /// - Returns: Zero when in the `identity` case, -1.0 for `willAppear`,
    ///   and 1.0 for `didDisappear`.
    public var value: Double {
        switch self {
        case .willAppear: return -1
        case .identity: return 0
        case .didDisappear: return 1
        }
    }
}

/// The properties a ``Transition`` can have.
///
/// High-level facts about a transition, for features that change how
/// transitions run to act on. `hasMotion` is what a reduced-motion setting
/// would replace with a fade; NucleantUI has no such setting yet, so no
/// transition is replaced today.
public struct TransitionProperties: Sendable {

    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }

    /// Whether the transition includes motion.
    ///
    /// Defaults to `true`.
    public var hasMotion: Bool
}

// MARK: - What the framework knows of its own transitions

/// The transitions NucleantUI provides, saying what is known of them
/// without building their body.
///
/// Nothing a user writes conforms, and nothing is asked of such a
/// transition beyond `Transition` itself: it is taken to change its view in
/// `identity` — so its body stays on the view the whole time it is shown,
/// as `TransitionPhase` describes — and to carry no animation of its own.
@MainActor
protocol BuiltinTransition: Transition {

    /// Whether `body(content:phase: .identity)` leaves its view exactly as
    /// it is — so a container need only build the body while the view
    /// arrives or leaves.
    static var identityLeavesViewUnchanged: Bool { get }

    /// Whether an animation attached with `animation(_:)` drives the view's
    /// arrival — so the arrival runs even when the change that inserted the
    /// view is not animated.
    static var animatesArrival: Bool { get }

    /// The same for the view's removal, and for its return while it is
    /// leaving.
    static var animatesRemoval: Bool { get }
}

extension Transition {

    /// `identityLeavesViewUnchanged` for one of the framework's transitions;
    /// `false` — its body stays on — for any other.
    static var leavesViewUnchangedAtIdentity: Bool {
        (Self.self as? any BuiltinTransition.Type)?.identityLeavesViewUnchanged ?? false
    }

    /// `animatesArrival` for one of the framework's transitions; `false`
    /// for any other.
    static var hasAnimatedArrival: Bool {
        (Self.self as? any BuiltinTransition.Type)?.animatesArrival ?? false
    }

    /// `animatesRemoval` for one of the framework's transitions; `false`
    /// for any other.
    static var hasAnimatedRemoval: Bool {
        (Self.self as? any BuiltinTransition.Type)?.animatesRemoval ?? false
    }
}
