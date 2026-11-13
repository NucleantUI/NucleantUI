//
//  AppearanceModifiers.swift
//  NucleantUI
//

extension View {

    /// Puts `background` behind this view, stretched to this view's size.
    public func background<B: View>(
        _ background: B,
        alignment: Alignment = .center
    ) -> some View {
        _DecoratedView(
            content: self,
            decoration: background,
            order: .background,
            alignment: alignment
        )
    }

    public func background<B: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ background: () -> B
    ) -> some View {
        self.background(background(), alignment: alignment)
    }

    /// Draws `overlay` on top of this view.
    public func overlay<O: View>(
        _ overlay: O,
        alignment: Alignment = .center
    ) -> some View {
        _DecoratedView(
            content: self,
            decoration: overlay,
            order: .overlay,
            alignment: alignment
        )
    }

    public func overlay<O: View>(
        alignment: Alignment = .center,
        @ViewBuilder _ overlay: () -> O
    ) -> some View {
        self.overlay(overlay(), alignment: alignment)
    }

    /// `style` filling a rectangle behind this view, stretched to its size.
    public func background(_ style: ShapeStyle) -> some View {
        background(Rectangle().fill(style))
    }

    /// A stroked outline just inside this view's bounds.
    public func border(_ color: Color, width: Double = 1, cornerRadius: Double = 0) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color, lineWidth: width)
        )
    }

    public func border(_ style: ShapeStyle, width: Double = 1, cornerRadius: Double = 0) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(style, lineWidth: width)
        )
    }

    public func opacity(_ opacity: Double) -> some View {
        _ModifierView(content: self, modifier: OpacityModifier(opacity: opacity))
    }

    /// Laid out as usual, drawn not at all.
    public func hidden() -> some View {
        _ModifierView(content: self, modifier: HiddenModifier())
    }

    /// Offset this view by the horizontal and vertical amount specified in
    /// the offset parameter.
    ///
    /// Moves the drawing — and where the view is hit, and where it is
    /// measured from outside — without disturbing the layout: the view's
    /// place, and every other view's, stays where layout put it. A change
    /// animates the offset itself.
    public func offset(_ offset: Size) -> some View {
        _ModifierView(content: self, modifier: OffsetModifier(offset: offset))
    }

    /// Offset this view by the specified horizontal and vertical distances.
    ///
    /// Moves the drawing — and where the view is hit, and where it is
    /// measured from outside — without disturbing the layout. A change
    /// animates the offset itself.
    public func offset(x: Double = 0, y: Double = 0) -> some View {
        _ModifierView(content: self, modifier: OffsetXYModifier(x: x, y: y))
    }

    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        _ModifierView(content: self, modifier: RotationEffectModifier(angle: angle, anchor: anchor))
    }

    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> some View {
        scaleEffect(x: scale, y: scale, anchor: anchor)
    }

    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> some View {
        _ModifierView(content: self, modifier: ScaleEffectModifier(x: x, y: y, anchor: anchor))
    }

    /// Clips to this view's bounds.
    public func clipped() -> some View {
        _ModifierView(content: self, modifier: ClippedModifier())
    }

    /// Rounds the corners and clips to them.
    public func cornerRadius(_ radius: Double) -> some View {
        _ModifierView(content: self, modifier: CornerRadiusModifier(radius: radius))
    }

    /// Clips to a shape. Only the shape's bounding box (with its corner
    /// rounding, for a `RoundedRectangle` or `Capsule`) is honoured — ThorVG
    /// clips against a clipper paint, and a rect is what the display list
    /// carries.
    public func clipShape<S: Shape>(_ shape: S) -> some View {
        _ModifierView(content: self, modifier: ClipShapeModifier(cornerRadius: Self.clipCornerRadius(for: shape)))
    }

    private static func clipCornerRadius<S: Shape>(for shape: S) -> Double {
        switch shape {
        case let rounded as RoundedRectangle: return rounded.cornerRadius
        // A capsule's radius depends on the box it lands in, which isn't known
        // until placement; a large radius is clamped there.
        case is Capsule, is Circle, is Ellipse: return .greatestFiniteMagnitude
        default: return 0
        }
    }
}

/// `.opacity(_:)`, animated.
struct OpacityModifier: PrimitiveModifier, Equatable {
    let opacity: Double

    func makeContent(_ context: inout BuildContext) -> OpacityContent {
        OpacityContent(opacity: context.animatedState(.opacity, opacity))
    }
}

/// `.hidden()`.
struct HiddenModifier: PrimitiveModifier, Equatable {
    func makeContent(_ context: inout BuildContext) -> HiddenContent {
        HiddenContent()
    }
}

/// `.offset(_:)`, animated.
struct OffsetModifier: PrimitiveModifier, Equatable {
    let offset: Size

    func makeContent(_ context: inout BuildContext) -> OffsetContent {
        OffsetContent(offset: context.animatedState(.offset, AnimatablePair(offset.width, offset.height)))
    }
}

/// `.offset(x:y:)`, animated.
struct OffsetXYModifier: PrimitiveModifier, Equatable {
    let x: Double
    let y: Double

    func makeContent(_ context: inout BuildContext) -> OffsetContent {
        OffsetContent(offset: context.animatedState(.offset, AnimatablePair(x, y)))
    }
}

/// `.rotationEffect(_:anchor:)`, animated.
struct RotationEffectModifier: PrimitiveModifier, Equatable {
    let angle: Angle
    let anchor: UnitPoint

    func makeContent(_ context: inout BuildContext) -> TransformContent {
        TransformContent(kind: .rotation(context.animatedState(.rotation, angle.radians)), anchor: anchor)
    }
}

/// `.scaleEffect(x:y:anchor:)`, animated.
struct ScaleEffectModifier: PrimitiveModifier, Equatable {
    let x: Double
    let y: Double
    let anchor: UnitPoint

    func makeContent(_ context: inout BuildContext) -> TransformContent {
        TransformContent(kind: .scale(context.animatedState(.scale, AnimatablePair(x, y))), anchor: anchor)
    }
}

/// `.clipped()`.
struct ClippedModifier: PrimitiveModifier, Equatable {
    func makeContent(_ context: inout BuildContext) -> ClipContent {
        ClipContent(cornerRadius: 0)
    }
}

/// `.cornerRadius(_:)`.
struct CornerRadiusModifier: PrimitiveModifier, Equatable {
    let radius: Double

    func makeContent(_ context: inout BuildContext) -> ClipContent {
        ClipContent(cornerRadius: radius)
    }
}

/// `.clipShape(_:)`, as the corner rounding of the shape's box.
struct ClipShapeModifier: PrimitiveModifier, Equatable {
    let cornerRadius: Double

    func makeContent(_ context: inout BuildContext) -> ClipContent {
        ClipContent(cornerRadius: cornerRadius)
    }
}
