//
//  VisualEffect.swift
//  NucleantUI
//
//  Visual effects: changes to how a view is drawn that leave its layout
//  alone — a move, a scale, a turn, a fade — built as values from
//  `EmptyVisualEffect` and applied while the view is placed, so they can
//  depend on where it was placed (`.visualEffect`) or on how far it is
//  into a scroll view (`.scrollTransition`). Each effect wraps the ones
//  written before it; applied, it puts its own change on the draw context
//  first, as a modifier written after another is the outer one.
//
//  The effects here are the ones NucleantUI draws for views: offset,
//  scale, rotation, an affine transform and opacity. Blur, the color
//  effects, blend modes and 3D rotation have no view-level drawing yet.
//

/// Visual Effects change the visual appearance of a view without changing its
/// ancestors or descendents.
///
/// Because effects do not impact layout, they are safe to use in situations
/// where layout modification is not allowed. For example, effects may be
/// applied as a function of position, accessed through a geometry proxy:
///
/// ```swift
/// var body: some View {
///     ContentRow()
///         .visualEffect { content, geometryProxy in
///             content.offset(x: geometryProxy.frame(in: .global).origin.y)
///         }
/// }
/// ```
///
/// You don't conform to this protocol yourself. Instead, visual effects are
/// created by calling modifier functions (such as `.offset(x:y:)` on other
/// effects, as seen in the example above.
public protocol VisualEffect: Sendable, Animatable {
    /// Put this effect, and the ones it wraps, on `context` for a view
    /// placed at `rect`.
    func _apply(to context: inout DrawContext, in rect: Rect)
}

/// The base visual effect that you apply additional effect to.
///
/// `EmptyVisualEffect` does not change the appearance of the view
/// that it is applied to.
public struct EmptyVisualEffect: VisualEffect {
    public typealias AnimatableData = EmptyAnimatableData

    /// Creates a new empty visual effect.
    public init() {}

    public func _apply(to context: inout DrawContext, in rect: Rect) {}
}

extension VisualEffect {
    /// Returns an effect that offsets the view by the given amount.
    public func offset(_ offset: Size) -> some VisualEffect {
        OffsetVisualEffect(base: self, offset: offset)
    }

    /// Returns an effect that offsets the view by the given horizontal and
    /// vertical distances.
    public func offset(x: Double = 0, y: Double = 0) -> some VisualEffect {
        OffsetVisualEffect(base: self, offset: Size(width: x, height: y))
    }

    /// Returns an effect that scales the view by the given factors, relative
    /// to an anchor point.
    public func scaleEffect(_ scale: Size, anchor: UnitPoint = .center) -> some VisualEffect {
        ScaleVisualEffect(base: self, scale: scale, anchor: anchor)
    }

    /// Returns an effect that scales the view by the given factor along both
    /// axes, relative to an anchor point.
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> some VisualEffect {
        ScaleVisualEffect(base: self, scale: Size(width: scale, height: scale), anchor: anchor)
    }

    /// Returns an effect that scales the view by the given horizontal and
    /// vertical factors, relative to an anchor point.
    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> some VisualEffect {
        ScaleVisualEffect(base: self, scale: Size(width: x, height: y), anchor: anchor)
    }

    /// Returns an effect that rotates the view by the given angle, around an
    /// anchor point.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some VisualEffect {
        RotationVisualEffect(base: self, angle: angle, anchor: anchor)
    }

    /// Returns an effect that applies `transform` to the view, about its
    /// top-leading corner.
    public func transformEffect(_ transform: Transform) -> some VisualEffect {
        TransformVisualEffect(base: self, transform: transform)
    }

    /// Returns an effect that sets the transparency of the view.
    ///
    /// - Parameter opacity: A value between 0 (fully transparent) and 1
    ///   (fully opaque).
    public func opacity(_ opacity: Double) -> some VisualEffect {
        OpacityVisualEffect(base: self, opacity: opacity)
    }
}

/// `.offset` on an effect.
struct OffsetVisualEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var offset: Size

    var animatableData: AnimatablePair<Base.AnimatableData, AnimatablePair<Double, Double>> {
        get { AnimatablePair(base.animatableData, AnimatablePair(offset.x, offset.y)) }
        set {
            base.animatableData = newValue.first
            offset = Size(width: newValue.second.first, height: newValue.second.second)
        }
    }

    func _apply(to context: inout DrawContext, in rect: Rect) {
        if offset != .zero {
            context.transform = context.transform.concatenating(.translation(x: offset.x, y: offset.y))
        }
        base._apply(to: &context, in: rect)
    }
}

/// `.scaleEffect` on an effect.
struct ScaleVisualEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var scale: Size
    let anchor: UnitPoint

    var animatableData: AnimatablePair<Base.AnimatableData, AnimatablePair<Double, Double>> {
        get { AnimatablePair(base.animatableData, AnimatablePair(scale.x, scale.y)) }
        set {
            base.animatableData = newValue.first
            scale = Size(width: newValue.second.first, height: newValue.second.second)
        }
    }

    func _apply(to context: inout DrawContext, in rect: Rect) {
        if scale != Size(width: 1, height: 1) {
            context.transform = context.transform
                .concatenating(.around(anchor.resolved(in: rect), .scale(x: scale.x, y: scale.y)))
        }
        base._apply(to: &context, in: rect)
    }
}

/// `.rotationEffect` on an effect.
struct RotationVisualEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var angle: Angle
    let anchor: UnitPoint

    var animatableData: AnimatablePair<Base.AnimatableData, Double> {
        get { AnimatablePair(base.animatableData, angle.radians) }
        set {
            base.animatableData = newValue.first
            angle = .radians(newValue.second)
        }
    }

    func _apply(to context: inout DrawContext, in rect: Rect) {
        if angle.radians != 0 {
            context.transform = context.transform
                .concatenating(.around(anchor.resolved(in: rect), .rotation(angle)))
        }
        base._apply(to: &context, in: rect)
    }
}

/// `.transformEffect` on an effect: not animated, as a matrix has no
/// meaningful in-between.
struct TransformVisualEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    let transform: Transform

    var animatableData: AnimatablePair<Base.AnimatableData, EmptyAnimatableData> {
        get { AnimatablePair(base.animatableData, EmptyAnimatableData()) }
        set { base.animatableData = newValue.first }
    }

    func _apply(to context: inout DrawContext, in rect: Rect) {
        context.transform = context.transform.concatenating(.around(rect.origin, transform))
        base._apply(to: &context, in: rect)
    }
}

/// `.opacity` on an effect.
struct OpacityVisualEffect<Base: VisualEffect>: VisualEffect {
    var base: Base
    var opacity: Double

    var animatableData: AnimatablePair<Base.AnimatableData, Double> {
        get { AnimatablePair(base.animatableData, opacity) }
        set {
            base.animatableData = newValue.first
            opacity = newValue.second
        }
    }

    func _apply(to context: inout DrawContext, in rect: Rect) {
        context.opacity *= min(max(opacity, 0), 1)
        base._apply(to: &context, in: rect)
    }
}

// MARK: - .visualEffect

extension View {
    /// Applies effects to this view, while providing access to layout
    /// information through a geometry proxy.
    ///
    /// You return new effects by calling functions on the first argument
    /// provided to the `effect` closure. In this example, `ContentRow` is
    /// offset by its own size, causing its top left corner to appear where
    /// the bottom right corner was originally located:
    /// ```swift
    /// var body: some View {
    ///     ContentRow()
    ///         .visualEffect { content, geometryProxy in
    ///             content.offset(geometryProxy.size)
    ///         }
    /// }
    /// ```
    ///
    /// The closure runs each time the view is placed — a scroll that moves
    /// it runs it again — on the main actor.
    ///
    /// - Parameters:
    ///   - effect: A closure that returns the effect to be applied. The first
    ///     argument provided to the closure is a placeholder representing
    ///     this view. The second argument is a `GeometryProxy`.
    /// - Returns: A view with the effect applied.
    public func visualEffect<Effect: VisualEffect>(
        _ effect: @escaping @MainActor (EmptyVisualEffect, GeometryProxy) -> Effect
    ) -> some View {
        _ModifierView(content: self, modifier: VisualEffectModifier(effect: effect))
    }
}

struct VisualEffectModifier<Effect: VisualEffect>: PrimitiveModifier {
    let effect: @MainActor (EmptyVisualEffect, GeometryProxy) -> Effect

    func makeContent(_ context: inout BuildContext) -> VisualEffectContent<Effect> {
        VisualEffectContent(effect: effect)
    }

    /// Built again whenever its parent is, for the latest closure.
    func _isEquivalent(to other: VisualEffectModifier<Effect>) -> Bool { false }
}

/// Asks for the effect with where the view is placed, and places the view
/// under it.
struct VisualEffectContent<Effect: VisualEffect>: NodeContent {
    let effect: @MainActor (EmptyVisualEffect, GeometryProxy) -> Effect

    func place(node: ViewNode, in rect: Rect, proposal: ProposedSize, context: DrawContext, into list: inout DisplayList) {
        let proxy = GeometryProxy(
            geometry: PlacedGeometry(rect: rect, transform: context.transform, spaces: context.coordinateSpaces),
            log: nil
        )
        var inner = context
        effect(EmptyVisualEffect(), proxy)._apply(to: &inner, in: rect)
        node.singleChild?.place(in: rect, proposal: proposal, context: inner, into: &list)
    }
}
