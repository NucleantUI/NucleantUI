//
//  ScrollTransition.swift
//  NucleantUI
//
//  `.scrollTransition`: a visual effect worked out from how far a view is
//  into the scroll view around it. Each time the view is placed, it is
//  measured against the scroll view's edge it is nearer: from just outside
//  it (hidden) to as far in as the configuration's threshold (visible). An
//  interactive transition draws the effect for the edge's phase and the
//  one for `identity`, and shows the view part of the way between them; an
//  animated one switches phase at the threshold and animates there.
//

/// The configuration of a scroll transition that controls how a transition
/// is applied as a view is scrolled through the visible region of a containing
/// scroll view or other container.
public struct ScrollTransitionConfiguration: Sendable {

    enum Kind: Sendable {
        case interactive(UnitCurve)
        case animated
        case identity
    }

    let kind: Kind
    let animation: Animation?
    let threshold: Threshold

    /// Creates a new configuration that discretely animates the transition
    /// when the view becomes visible.
    ///
    /// Unlike the interactive configuration, the transition isn't
    /// interpolated as the scroll view is scrolled. Instead, the transition
    /// phase only changes once the threshold has been reached, at which
    /// time the given animation is used to animate to the new phase.
    ///
    /// - Parameters:
    ///   - animation: The animation to use when transitioning between states.
    ///
    /// - Returns: A configuration that discretely animates between
    ///   transition phases.
    public static func animated(_ animation: Animation = .default) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(kind: .animated, animation: animation, threshold: .visible)
    }

    /// Creates a new configuration that discretely animates the transition
    /// when the view becomes visible.
    public static let animated = ScrollTransitionConfiguration.animated(.default)

    /// Creates a new configuration that interactively interpolates the
    /// transition's effect as the view is scrolled into the visible region
    /// of the container.
    ///
    /// - Parameters:
    ///   - timingCurve: The curve that adjusts the pace at which the effect
    ///     is interpolated between phases of the transition. For example, an
    ///     `.easeIn` curve causes interpolation to begin slowly as the view
    ///     reaches the edge of the scroll view, then speed up as it reaches
    ///     the visible threshold. The curve is applied 'forward' while the
    ///     view is appearing, meaning that time zero corresponds to the
    ///     view being just hidden, and time 1.0 corresponds to the pont at
    ///     which the view reaches the configuration threshold. This also means
    ///     that the timing curve is applied in reversed while the view
    ///     is moving away from the center of the scroll view.
    ///
    /// - Returns: A configuration that interactively interpolates between
    ///   transition phases based on the current scroll position.
    public static func interactive(timingCurve: UnitCurve = .easeInOut) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(kind: .interactive(timingCurve), animation: nil, threshold: .visible)
    }

    /// Creates a new configuration that interactively interpolates the
    /// transition's effect as the view is scrolled into the visible region
    /// of the container.
    public static let interactive = ScrollTransitionConfiguration.interactive(timingCurve: .easeInOut)

    /// Creates a new configuration that does not change the appearance of the view.
    public static let identity = ScrollTransitionConfiguration(kind: .identity, animation: nil, threshold: .visible)

    /// Sets the animation with which the transition will be applied.
    ///
    /// For an animated configuration, this is the animation it switches
    /// phase along. An interactive one follows the scroll position as it is
    /// — the effect does not lag behind it here.
    ///
    /// - Parameter animation: An animation that will be used to apply the
    ///   transition to the view.
    ///
    /// - Returns: A copy of this configuration with the animation set to the
    ///   given value.
    public func animation(_ animation: Animation) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(kind: kind, animation: animation, threshold: threshold)
    }

    /// Sets the threshold at which the view will be considered fully visible.
    ///
    /// - Parameters:
    ///   - threshold: The threshold specifying how much of the view must
    ///     intersect with the container before it is treated as visible.
    ///
    /// - Returns: A copy of this configuration with the threshold set to the
    ///   given value.
    public func threshold(_ threshold: Threshold) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(kind: kind, animation: animation, threshold: threshold)
    }
}

extension ScrollTransitionConfiguration {

    /// Describes a specific point in the progression of a target view within a container
    /// from hidden (fully outside the container) to visible.
    public struct Threshold: Sendable {

        indirect enum Kind: Sendable {
            /// Visible by this share of its length, 0…1.
            case visible(Double)
            case centered
            case interpolated(Kind, Kind, amount: Double)
            case inset(Kind, by: Double)
        }

        let kind: Kind

        /// The target view is fully visible.
        public static let visible = Threshold(kind: .visible(1))

        /// The target view is fully outside the container.
        public static let hidden = Threshold(kind: .visible(0))

        /// The target view is centered within the container
        public static var centered: Threshold { Threshold(kind: .centered) }

        /// The target view is visible by the given amount, where zero is fully
        /// hidden, and one is fully visible.
        ///
        /// Values less than zero or greater than one are clamped.
        public static func visible(_ amount: Double) -> Threshold {
            Threshold(kind: .visible(min(max(amount, 0), 1)))
        }

        /// Creates a new threshold that combines this threshold value with
        /// another threshold, interpolated by the given amount.
        ///
        /// - Parameters:
        ///   - other: The second threshold value.
        ///   - amount: The ratio with which this threshold is combined with
        ///     the given threshold, where zero is equal to this threshold,
        ///     1.0 is equal to `other`, and values in between combine the two
        ///     thresholds.
        public func interpolated(towards other: Threshold, amount: Double) -> Threshold {
            Threshold(kind: .interpolated(kind, other.kind, amount: amount))
        }

        /// Returns a threshold that is met when the target view is closer to the
        /// center of the container by `distance`. Use negative values to move
        /// the threshold away from the center.
        public func inset(by distance: Double) -> Threshold {
            Threshold(kind: .inset(kind, by: distance))
        }

        /// How far into a container `container` long a view `length` long
        /// has to be — from just outside the edge it is coming in at — to
        /// meet this threshold.
        func distance(container: Double, length: Double) -> Double {
            Self.distance(of: kind, container: container, length: length)
        }

        private static func distance(of kind: Kind, container: Double, length: Double) -> Double {
            switch kind {
            case .visible(let amount):
                // A view longer than the container is never all in view.
                return min(amount * length, container)
            case .centered:
                return (container + length) / 2
            case .interpolated(let from, let to, let amount):
                let start = distance(of: from, container: container, length: length)
                let end = distance(of: to, container: container, length: length)
                return start + (end - start) * amount
            case .inset(let base, let by):
                return distance(of: base, container: container, length: length) + by
            }
        }
    }
}

/// The phases that a view transitions between when it scrolls among other views.
///
/// When a view with a scroll transition modifier applied is approaching
/// the visible region of the containing scroll view or other container,
/// the effect  will first be applied with the `topLeading` or `bottomTrailing`
/// phase (depending on which edge the view is approaching), then will be
/// moved to the `identity` phase as the view moves into the visible area. The
/// timing and behavior that determines when a view is visible within the
/// container is controlled by the configuration that is provided to the
/// `scrollTransition` modifier.
///
/// In the `identity` phase, scroll transitions should generally not make any
/// visual change to the view they are applied to, since the transition's view
/// modifications in the `identity` phase will be applied to the view as long
/// as it is visible. In the `topLeading` and `bottomTrailing` phases,
/// transitions should apply a change that will be animated to create the
/// transition.
public enum ScrollTransitionPhase: Hashable, Sendable {
    /// The scroll transition is being applied to a view that is about to
    /// move into the visible area at the top edge of a vertical scroll view,
    /// or the leading edge of a horizont scroll view.
    case topLeading

    /// The scroll transition is being applied to a view that is in the
    /// visible area.
    ///
    /// In this phase, a transition should show its steady state appearance,
    /// which will generally not make any visual change to the view.
    case identity

    /// The scroll transition is being applied to a view that is about to
    /// move into the visible area at the bottom edge of a vertical scroll
    /// view, or the trailing edge of a horizontal scroll view.
    case bottomTrailing

    public var isIdentity: Bool { self == .identity }

    /// A phase-derived value that can be used to scale or otherwise modify
    /// effects.
    ///
    /// Returns -1.0 when in the topLeading phase, zero when in the identity
    /// phase, and 1.0 when in the bottomTrailing phase.
    public var value: Double {
        switch self {
        case .topLeading: -1
        case .identity: 0
        case .bottomTrailing: 1
        }
    }
}

// MARK: - The modifiers

extension View {
    /// Applies the given transition, animating between the phases
    /// of the transition as this view appears and disappears within the
    /// visible region of the containing scroll view.
    ///
    /// - Parameters:
    ///   - configuration: The configuration controlling how the
    ///     transition will be applied. The configuration will be applied both
    ///     while the view is coming into view and while it is disappearing (the
    ///     transition is symmetrical).
    ///   - axis: The axis of the containing scroll view over which the
    ///     transition will be applied. The default value of `nil` uses the
    ///     axis of the innermost containing scroll view, or `.vertical` if
    ///     the innermost scroll view is scrollable along both axes.
    ///   - transition: A closure that applies visual effects as a function of
    ///     the provided phase. It runs on the main actor, as the view is
    ///     placed.
    public func scrollTransition<Effect: VisualEffect>(
        _ configuration: ScrollTransitionConfiguration = .interactive,
        axis: Axis? = nil,
        transition: @escaping @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollTransitionModifier(
            configuration: configuration, axis: axis, transition: transition
        ))
    }

    /// Applies the given transition, animating between the phases
    /// of the transition as this view appears and disappears within the
    /// visible region of the containing scroll view.
    ///
    /// - Parameters:
    ///   - topLeading: The configuration that drives the transition when
    ///     the view is about to appear at the top edge of a vertical
    ///     scroll view, or the leading edge of a horizont scroll view.
    ///   - bottomTrailing: The configuration that drives the transition when
    ///     the view is about to appear at the bottom edge of a vertical
    ///     scroll view, or the trailing edge of a horizont scroll view.
    ///   - axis: The axis of the containing scroll view over which the
    ///     transition will be applied. The default value of `nil` uses the
    ///     axis of the innermost containing scroll view, or `.vertical` if
    ///     the innermost scroll view is scrollable along both axes.
    ///   - transition: A closure that applies visual effects as a function of
    ///     the provided phase.
    public func scrollTransition<Effect: VisualEffect>(
        topLeading: ScrollTransitionConfiguration,
        bottomTrailing: ScrollTransitionConfiguration,
        axis: Axis? = nil,
        transition: @escaping @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
    ) -> some View {
        _ModifierView(content: self, modifier: EdgeScrollTransitionModifier(
            topLeading: topLeading, bottomTrailing: bottomTrailing, axis: axis, transition: transition
        ))
    }
}

/// Where a view is in the scroll view around it, for a scroll transition.
@MainActor
struct ScrollTransitionPlacement {
    /// The edge it is nearer, as the phase it is coming in from there.
    let edge: ScrollTransitionPhase
    /// How far in from that edge it is, from just outside it; and the
    /// length of the scroll view and of the view along the axis.
    let distance: Double
    let container: Double
    let length: Double

    /// Measured along `axis` — or the innermost scroll view's own, its
    /// vertical one when it scrolls both ways — for a view placed at
    /// `rect` under `context`; `nil` outside any scroll view.
    init?(rect: Rect, context: DrawContext, axis: Axis?) {
        let spaces = context.coordinateSpaces
        guard let index = spaces.lastIndex(where: { $0.name == AnyHashable(ScrollViewSpaceName(axis: nil)) }) else { return nil }
        let scroll = spaces[index]
        let resolved: Axis
        if let axis {
            resolved = axis
        } else {
            // The axis names it gave its space, right after it.
            let own = spaces[(index + 1)...]
            let horizontal = own.contains { $0.name == AnyHashable(ScrollViewSpaceName(axis: .horizontal)) }
            let vertical = own.contains { $0.name == AnyHashable(ScrollViewSpaceName(axis: .vertical)) }
            resolved = horizontal && !vertical ? .horizontal : .vertical
        }
        let proxy = GeometryProxy(
            geometry: PlacedGeometry(rect: rect, transform: context.transform, spaces: spaces, safeArea: context.safeArea),
            log: nil
        )
        let frame = proxy.frame(in: .scrollView)
        let start = frame.origin[resolved]
        let length = frame.size[resolved]
        let container = scroll.rect.size[resolved]
        if start + length / 2 > container / 2 {
            edge = .bottomTrailing
            distance = container - start
        } else {
            edge = .topLeading
            distance = start + length
        }
        self.container = container
        self.length = length
    }

    /// How far it is from hidden (0) to `threshold` (1).
    func progress(to threshold: ScrollTransitionConfiguration.Threshold) -> Double {
        let needed = threshold.distance(container: container, length: length)
        guard needed > 0 else { return distance > 0 ? 1 : 0 }
        return min(max(distance / needed, 0), 1)
    }
}

/// What an animated scroll transition is showing: its phase, and the move
/// to it under way.
struct AnimatedScrollTransition<Data: VectorArithmetic> {
    var phase: ScrollTransitionPhase
    var from: Data
    var to: Data
    var start: Double
    var animation: Animation?

    /// The effect's data at `now`, and whether it is still on its way.
    func data(at now: Double) -> (data: Data, isMoving: Bool) {
        guard let animation else { return (to, false) }
        let progress = animation.progress(after: now - start)
        if progress.isFinished { return (to, false) }
        return (from + (to - from).scaled(by: progress.fraction), true)
    }
}

/// `.scrollTransition(_:axis:transition:)`.
struct ScrollTransitionModifier<Effect: VisualEffect>: PrimitiveModifier {
    let configuration: ScrollTransitionConfiguration
    let axis: Axis?
    let transition: @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

    func makeContent(_ context: inout BuildContext) -> ScrollTransitionContent<Effect> {
        ScrollTransitionContent(placed: context.position.placed, configuration: configuration, axis: axis, transition: transition)
    }

    func _isEquivalent(to other: ScrollTransitionModifier<Effect>) -> Bool { false }
}

struct ScrollTransitionContent<Effect: VisualEffect>: NodeContent {
    /// An animated transition's state, kept on the view's position.
    let placed: PlacedValue
    let configuration: ScrollTransitionConfiguration
    let axis: Axis?
    let transition: @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        effect(rect: rect, context: context)._apply(to: &inner, in: rect)
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }

    private func effect(rect: Rect, context: DrawContext) -> Effect {
        let identity = transition(EmptyVisualEffect(), .identity)
        guard let placement = ScrollTransitionPlacement(rect: rect, context: context, axis: axis) else {
            return identity
        }
        let progress = placement.progress(to: configuration.threshold)
        switch configuration.kind {
        case .identity:
            return identity
        case .interactive(let curve):
            let edge = transition(EmptyVisualEffect(), placement.edge)
            let amount = curve.value(at: progress)
            var shown = edge
            shown.animatableData = edge.animatableData + (identity.animatableData - edge.animatableData).scaled(by: amount)
            return shown
        case .animated:
            let phase: ScrollTransitionPhase = progress >= 1 ? .identity : placement.edge
            let target = phase == .identity ? identity : transition(EmptyVisualEffect(), phase)
            let store = AnimationStore.current
            let now = store?.now ?? Scroller.now
            var state = placed.value?.value(as: AnimatedScrollTransition<Effect.AnimatableData>.self)
            if context.freezesMotion {
                // Drawn where it was: no change of phase starts.
            } else if state == nil {
                state = AnimatedScrollTransition(
                    phase: phase, from: target.animatableData, to: target.animatableData, start: now, animation: nil
                )
            } else if state?.phase != phase, let current = state {
                state = AnimatedScrollTransition(
                    phase: phase,
                    from: current.data(at: now).data,
                    to: target.animatableData,
                    start: now,
                    animation: configuration.animation
                )
            }
            guard let state else { return target }
            placed.value = Box(state)
            let shown = state.data(at: now)
            if shown.isMoving { store?.requestFrame() }
            var effect = target
            effect.animatableData = shown.data
            return effect
        }
    }
}

/// `.scrollTransition(topLeading:bottomTrailing:axis:transition:)`.
struct EdgeScrollTransitionModifier<Effect: VisualEffect>: PrimitiveModifier {
    let topLeading: ScrollTransitionConfiguration
    let bottomTrailing: ScrollTransitionConfiguration
    let axis: Axis?
    let transition: @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

    func makeContent(_ context: inout BuildContext) -> EdgeScrollTransitionContent<Effect> {
        EdgeScrollTransitionContent(
            placed: context.position.placed,
            topLeading: topLeading,
            bottomTrailing: bottomTrailing,
            axis: axis,
            transition: transition
        )
    }

    func _isEquivalent(to other: EdgeScrollTransitionModifier<Effect>) -> Bool { false }
}

struct EdgeScrollTransitionContent<Effect: VisualEffect>: NodeContent {
    let placed: PlacedValue
    let topLeading: ScrollTransitionConfiguration
    let bottomTrailing: ScrollTransitionConfiguration
    let axis: Axis?
    let transition: @MainActor (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        var inner = context
        effect(rect: rect, context: context)._apply(to: &inner, in: rect)
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }

    private func effect(rect: Rect, context: DrawContext) -> Effect {
        let identity = transition(EmptyVisualEffect(), .identity)
        guard let placement = ScrollTransitionPlacement(rect: rect, context: context, axis: axis) else {
            return identity
        }
        // The configuration of the edge the view is at.
        let configuration = placement.edge == .topLeading ? topLeading : bottomTrailing
        let progress = placement.progress(to: configuration.threshold)
        switch configuration.kind {
        case .identity:
            return identity
        case .interactive(let curve):
            let edge = transition(EmptyVisualEffect(), placement.edge)
            let amount = curve.value(at: progress)
            var shown = edge
            shown.animatableData = edge.animatableData + (identity.animatableData - edge.animatableData).scaled(by: amount)
            return shown
        case .animated:
            let phase: ScrollTransitionPhase = progress >= 1 ? .identity : placement.edge
            let target = phase == .identity ? identity : transition(EmptyVisualEffect(), phase)
            let store = AnimationStore.current
            let now = store?.now ?? Scroller.now
            var state = placed.value?.value(as: AnimatedScrollTransition<Effect.AnimatableData>.self)
            if context.freezesMotion {
                // Drawn where it was: no change of phase starts.
            } else if state == nil {
                state = AnimatedScrollTransition(
                    phase: phase, from: target.animatableData, to: target.animatableData, start: now, animation: nil
                )
            } else if state?.phase != phase, let current = state {
                state = AnimatedScrollTransition(
                    phase: phase,
                    from: current.data(at: now).data,
                    to: target.animatableData,
                    start: now,
                    animation: configuration.animation
                )
            }
            guard let state else { return target }
            placed.value = Box(state)
            let shown = state.data(at: now)
            if shown.isMoving { store?.requestFrame() }
            var effect = target
            effect.animatableData = shown.data
            return effect
        }
    }
}
