//
//  ScrollObservers.swift
//  NucleantUI
//
//  Modifiers that watch a scroll view — its geometry, its phase, which
//  views of its scroll target layout are in view. Each, as it is placed,
//  puts an observer in the draw context; the first scroll view placed below
//  claims it and, once its content is placed, hands it what it saw. The
//  scroll view takes the observers away from its content, so a scroll view
//  inside it is not watched by them, and one beside it that comes later
//  finds them claimed. What the actions are handed is kept on the
//  modifier's position, so a value is passed on when it changes.
//

/// One observing modifier's ask of the first scroll view placed below it,
/// for one pass.
@MainActor
final class ScrollObserver {
    /// The observers of the modifiers above this one.
    let next: ScrollObserver?
    private(set) var isClaimed = false
    let observe: @MainActor (ScrollObservation) -> Void

    init(next: ScrollObserver?, observe: @escaping @MainActor (ScrollObservation) -> Void) {
        self.next = next
        self.observe = observe
    }

    /// Whether the scroll view asking is the first to: true once.
    func claim() -> Bool {
        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}

/// What a scroll view hands its observers once its content is placed.
@MainActor
struct ScrollObservation {
    let scroller: Scroller
    let geometry: ScrollGeometry
    /// The phases it went through since the last pass, in order.
    let phaseChanges: [Scroller.PhaseChange]
}

/// A type that provides you with more content when the phase of a scroll
/// view changes.
///
/// You don't create this type directly. Instead, SwiftUI provides an instance
/// of this type in the ``View/onScrollPhaseChange(_:)`` modifier.
public struct ScrollPhaseChangeContext: Sendable {
    /// The geometry of the scroll view at the time of the
    /// scroll phase change.
    public let geometry: ScrollGeometry

    /// The velocity of the scroll view at the time of the
    /// scroll phase change: the speed a finger let it go at, on the change
    /// into `decelerating`; `nil` on the others.
    public let velocity: Vector?
}

// MARK: - Geometry

extension View {
    /// Adds an action to be performed when a value, created from a
    /// scroll geometry, changes.
    ///
    /// The geometry of a scroll view changes frequently while scrolling.
    /// You should avoid updating large parts of your app whenever
    /// the scroll geometry changes. To aid in this, you provide two
    /// closures to this modifier:
    ///   * transform: This converts a value of ``ScrollGeometry`` to a
    ///     your own data type.
    ///   * action: This provides the data type you created in `of`
    ///     and is called whenever the data type changes.
    ///
    /// For example, you can use this modifier to know when the user scrolls
    /// a scroll view beyond the top of its content. In the following example,
    /// the data type you convert to is a ``Bool`` and the action is called
    /// whenever the ``Bool`` changes.
    ///
    ///     @Binding var isBeyondZero: Bool
    ///
    ///     ScrollView {
    ///         // ...
    ///     }
    ///     .onScrollGeometryChange(for: Bool.self) { geometry in
    ///         geometry.contentOffset.y < geometry.contentInsets.top
    ///     } action: { wasBeyondZero, isBeyondZero in
    ///         self.isBeyondZero = isBeyondZero
    ///     }
    ///
    /// If multiple scroll views are found within the view hierarchy,
    /// only the first one will invoke the closure you provide.
    ///
    /// The action also runs the first time the scroll view is placed, with
    /// the value it is placed with as both the old and the new value — as
    /// `onGeometryChange(for:of:action:)`'s does.
    ///
    /// - Parameters:
    ///   - type: The type of value transformed from a ``ScrollGeometry``.
    ///   - transform: A closure that transforms a ``ScrollGeometry``
    ///     to your type.
    ///   - action: A closure to run when the transformed data changes.
    ///   - oldValue: The old value that failed the comparison check.
    ///   - newValue: The new value that failed the comparison check.
    public func onScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping @MainActor (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollGeometryChangeModifier(transform: transform, action: action))
    }
}

struct ScrollGeometryChangeModifier<T: Equatable>: PrimitiveModifier {
    let transform: (ScrollGeometry) -> T
    let action: @MainActor (T, T) -> Void

    func makeContent(_ context: inout BuildContext) -> ScrollGeometryChangeContent<T> {
        ScrollGeometryChangeContent(placed: context.position.placed, effects: context.effects, transform: transform, action: action)
    }

    /// Built again whenever its parent is, for the latest closures.
    func _isEquivalent(to other: ScrollGeometryChangeModifier<T>) -> Bool { false }
}

struct ScrollGeometryChangeContent<T: Equatable>: NodeContent {
    /// The value worked out last, kept on the modifier's position.
    let placed: PlacedValue
    let effects: EffectQueue
    let transform: (ScrollGeometry) -> T
    let action: @MainActor (T, T) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        var inner = context
        if !context.freezesMotion {
            let placed = placed, effects = effects, transform = transform, action = action
            inner.scrollObservers = ScrollObserver(next: context.scrollObservers) { observation in
                effects.onGeometryTransition(placed, to: transform(observation.geometry), action)
            }
        }
        child.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

// MARK: - Phase

extension View {
    /// Adds an action to perform when the scroll phase of the first scroll
    /// view in the hierarchy changes.
    ///
    /// Use this modifier to be informed of changes to a scroll view's
    /// phase. A scroll view may be in a variety of different phases like
    /// panning or decelerating. See ``ScrollPhase`` for more information
    /// on the phases of a scroll view.
    ///
    /// When the phase of a scroll view changes, the system invokes the action
    /// you provide. In the following example, a selection binding is updated
    /// when the scroll view transitions to the ``ScrollPhase/decelerating``
    /// or ``ScrollPhase/idle`` phase.
    ///
    ///     @Binding var selection: SelectionValue?
    ///
    ///     ScrollView {
    ///         // ...
    ///     }
    ///     .onScrollPhaseChange { _, newPhase in
    ///         if newPhase == .decelerating || newPhase == .idle {
    ///             selection = updateSelection()
    ///         }
    ///     }
    ///
    /// If multiple scroll views are found within the view hierarchy,
    /// only the first one will invoke the closure you provide.
    ///
    /// - Parameters:
    ///   - action: A closure to run when the scroll phase changes.
    ///   - oldPhase: The old scroll phase.
    ///   - newPhase: The new scroll phase.
    public func onScrollPhaseChange(
        _ action: @escaping @MainActor (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollPhaseChangeModifier(action: action))
    }

    /// Adds an action to perform when the scroll phase of the first scroll
    /// view in the hierarchy changes.
    ///
    /// Use this modifier to be informed of changes to a scroll view's
    /// phase. A scroll view may be in a variety of different phases like
    /// interacting or decelerating. See ``ScrollPhase`` for more information
    /// on the phases of a scroll view.
    ///
    /// The system can also provide you with a context containing
    /// the geometry of the scroll view at the time of the phase change.
    /// You can use the geometry to understand where the scroll view
    /// has come or gone between the phase changes and update
    /// dependent state on that information. In the following example,
    /// whether toolbar content is hidden is determined based on
    /// the direction of the last user initiated scroll.
    ///
    ///     @Binding var hidesToolbarContent: Bool
    ///     @State private var lastOffset: CGFloat = 0.0
    ///
    ///     ScrollView {
    ///         // ...
    ///     }
    ///     .onScrollPhaseChange { oldPhase, newPhase, context in
    ///         if newPhase == .interacting {
    ///             lastOffset = context.geometry.contentOffset.y
    ///         }
    ///         if oldPhase == .interacting, newPhase != .animating,
    ///             context.geometry.contentOffset.y - lastOffset < 0.0
    ///         {
    ///             hidesToolbarContent = true
    ///         } else {
    ///             hidesToolbarContent = false
    ///         }
    ///     }
    ///
    /// If multiple scroll views are found within the view hierarchy,
    /// only the first one will invoke the closure you provide.
    ///
    /// - Parameters:
    ///   - action: A closure to run when the scroll phase changes.
    ///   - oldPhase: The old scroll phase.
    ///   - newPhase: The new scroll phase.
    ///   - context: The phase context at the time of the scroll
    ///     phase change.
    public func onScrollPhaseChange(
        _ action: @escaping @MainActor (
            _ oldPhase: ScrollPhase, _ newPhase: ScrollPhase, _ context: ScrollPhaseChangeContext
        ) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollPhaseChangeWithContextModifier(action: action))
    }
}

/// `.onScrollPhaseChange(_:)` with an action of the two phases.
struct ScrollPhaseChangeModifier: PrimitiveModifier {
    let action: @MainActor (ScrollPhase, ScrollPhase) -> Void

    func makeContent(_ context: inout BuildContext) -> ScrollPhaseChangeContent {
        ScrollPhaseChangeContent(effects: context.effects, action: action)
    }

    func _isEquivalent(to other: ScrollPhaseChangeModifier) -> Bool { false }
}

struct ScrollPhaseChangeContent: NodeContent {
    let effects: EffectQueue
    let action: @MainActor (ScrollPhase, ScrollPhase) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        var inner = context
        if !context.freezesMotion {
            let effects = effects, action = action
            inner.scrollObservers = ScrollObserver(next: context.scrollObservers) { observation in
                for change in observation.phaseChanges {
                    effects.afterPass { action(change.old, change.new) }
                }
            }
        }
        child.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

/// `.onScrollPhaseChange(_:)` with an action of the two phases and the
/// context.
struct ScrollPhaseChangeWithContextModifier: PrimitiveModifier {
    let action: @MainActor (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void

    func makeContent(_ context: inout BuildContext) -> ScrollPhaseChangeWithContextContent {
        ScrollPhaseChangeWithContextContent(effects: context.effects, action: action)
    }

    func _isEquivalent(to other: ScrollPhaseChangeWithContextModifier) -> Bool { false }
}

struct ScrollPhaseChangeWithContextContent: NodeContent {
    let effects: EffectQueue
    let action: @MainActor (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        var inner = context
        if !context.freezesMotion {
            let effects = effects, action = action
            inner.scrollObservers = ScrollObserver(next: context.scrollObservers) { observation in
                for change in observation.phaseChanges {
                    let phaseContext = ScrollPhaseChangeContext(geometry: observation.geometry, velocity: change.velocity)
                    effects.afterPass { action(change.old, change.new, phaseContext) }
                }
            }
        }
        child.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

// MARK: - Target visibility

extension View {
    /// Adds an action to be called with information about what views would
    /// be considered visible.
    ///
    /// Use this modifier along with the modifier ``View/scrollTargetLayout()``
    /// to be informed when the views in the targetted scroll view have crossed
    /// the provided threshold to be considered on/off screen.
    ///
    ///     ScrollView {
    ///         LazyVStack {
    ///             ForEach(models) { model in
    ///                 CardView(model: model)
    ///             }
    ///         }
    ///         .scrollTargetLayout()
    ///     }
    ///     .onScrollTargetVisibilityChange(idType: Model.ID.self, threshold: 0.2) { onScreenCards in
    ///         // Disable video playback for cards that are offscreen...
    ///     }
    ///
    /// The action is also called the first time the scroll view is placed,
    /// with the views in view then.
    ///
    /// - Parameters:
    ///   - idType: The type of Identity provided by the subviews.
    ///   - threshold: The amount required to be visible within the viewport of the
    ///   the scrollview before the `action` is fired.  By default when the view
    ///   has crossed more than 50% on-screen, the action will be called.
    ///   - action: The action which will be called when the views within the
    ///   scroll view cross the provided threshold. The callback will include
    ///   which views are considered visible, in the layout's order.
    public func onScrollTargetVisibilityChange<ID: Hashable>(
        idType: ID.Type,
        threshold: Double = 0.5,
        _ action: @escaping @MainActor ([ID]) -> Void
    ) -> some View {
        _ModifierView(content: self, modifier: ScrollTargetVisibilityChangeModifier(threshold: threshold, action: action))
    }
}

struct ScrollTargetVisibilityChangeModifier<ID: Hashable>: PrimitiveModifier {
    let threshold: Double
    let action: @MainActor ([ID]) -> Void

    func makeContent(_ context: inout BuildContext) -> ScrollTargetVisibilityChangeContent<ID> {
        ScrollTargetVisibilityChangeContent(placed: context.position.placed, effects: context.effects, threshold: threshold, action: action)
    }

    func _isEquivalent(to other: ScrollTargetVisibilityChangeModifier<ID>) -> Bool { false }
}

struct ScrollTargetVisibilityChangeContent<ID: Hashable>: NodeContent {
    /// The ids in view last time, kept on the modifier's position.
    let placed: PlacedValue
    let effects: EffectQueue
    let threshold: Double
    let action: @MainActor ([ID]) -> Void

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        guard let child = node.singleChild else { return }
        var inner = context
        if !context.freezesMotion {
            let placed = placed, effects = effects, threshold = threshold, action = action
            inner.scrollObservers = ScrollObserver(next: context.scrollObservers) { observation in
                let visible = observation.geometry.visibleRect
                var ids: [ID] = []
                for (index, frame) in observation.scroller.targetFrames.enumerated() {
                    let fraction = frame.visibleFraction(in: visible)
                    guard fraction > 0, fraction >= threshold else { continue }
                    if let id = observation.scroller.targetNodes[index].scrollTargetID(as: ID.self) {
                        ids.append(id)
                    }
                }
                effects.onGeometryChange(placed, to: ids, action)
            }
        }
        child.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}

extension Rect {
    /// The share of this rect's area inside `visible`, from 0 to 1 — how
    /// much of a view is in view. A rect with no area is in view, all of
    /// it, when it lies inside.
    func visibleFraction(in visible: Rect) -> Double {
        let width = min(maxX, visible.maxX) - max(minX, visible.minX)
        let height = min(maxY, visible.maxY) - max(minY, visible.minY)
        let area = self.width * self.height
        guard area > 0 else {
            return width >= 0 && height >= 0 ? 1 : 0
        }
        guard width > 0, height > 0 else { return 0 }
        return min(1, width * height / area)
    }
}
