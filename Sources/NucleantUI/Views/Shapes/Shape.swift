//
//  Shape.swift
//  NucleantUI
//

/// A 2D shape that can be filled or stroked.
///
/// As in SwiftUI, a shape drawn as a view is handed its rect in its own
/// coordinate space — origin at its top-left corner — and the framework
/// moves the path to where the view was placed. The path then depends on the
/// shape and its size alone: one placed again at the same size is drawn
/// with the path it already made.
///
/// Every shape is `Animatable`: one that exposes `animatableData` is drawn
/// at each value in between when a change to it animates — its path is
/// made again every frame, nothing is rebuilt.
@MainActor
public protocol Shape: Animatable, View {
    func path(in rect: Rect) -> Path
}

/// A shape used directly as a view fills with the current foreground color,
/// the same default SwiftUI applies.
extension Shape {
    public var body: _ShapeView<Self> {
        _ShapeView(shape: self, fill: nil, stroke: nil, strokeStyle: StrokeStyle(), fillsWithForeground: true)
    }
}

extension Shape {
    /// Fill this shape with a style.
    public func fill(_ style: ShapeStyle) -> some View {
        _ShapeView(shape: self, fill: style, stroke: nil, strokeStyle: StrokeStyle())
    }

    public func fill(_ color: Color) -> some View {
        fill(.color(color))
    }

    /// Stroke this shape's outline.
    public func stroke(_ style: ShapeStyle, lineWidth: Double = 1) -> some View {
        _ShapeView(
            shape: self,
            fill: nil,
            stroke: style,
            strokeStyle: StrokeStyle(lineWidth: lineWidth)
        )
    }

    public func stroke(_ style: ShapeStyle, style strokeStyle: StrokeStyle) -> some View {
        _ShapeView(shape: self, fill: nil, stroke: style, strokeStyle: strokeStyle)
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> some View {
        stroke(.color(color), lineWidth: lineWidth)
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> some View {
        _ShapeView(shape: self, fill: nil, stroke: .color(color), strokeStyle: style)
    }
}

/// A shape with its paint resolved. Every `Shape` becomes one of these —
/// used bare, through its `body`, filled with the environment's foreground
/// color.
@View
public struct _ShapeView<S: Shape> {
    let shape: S
    let fill: ShapeStyle?
    let stroke: ShapeStyle?
    let strokeStyle: StrokeStyle
    /// Fill with the foreground color in effect, rather than `fill`.
    var fillsWithForeground: Bool = false

    public var body: Never { bodyUnavailable() }
}

extension _ShapeView: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let fill = fillsWithForeground ? context.environment.foregroundStyle : self.fill
        return ContentNode(content: ShapeContent(
            shape: shape,
            drawn: context.drawnShape(shape),
            fill: fill,
            stroke: stroke,
            strokeStyle: strokeStyle,
            idealSize: nil,
            animatedFill: context.animatedStyle(.fill, fill),
            animatedStroke: context.animatedStyle(.stroke, stroke)
        ))
    }
}

/// The built-in shapes, which are nodes themselves rather than a body.
extension Shape {
    func makeShapeNode(_ context: inout BuildContext) -> ViewNode {
        _ShapeView(shape: self, fill: nil, stroke: nil, strokeStyle: StrokeStyle(), fillsWithForeground: true)
            .makeNode(&context)
    }
}
