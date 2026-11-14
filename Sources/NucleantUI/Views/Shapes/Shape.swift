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

/// A shape used directly as a view fills with the foreground style in
/// effect, the same default SwiftUI applies.
extension Shape {
    public var body: _ShapeView<Self, ForegroundStyle> {
        _ShapeView(shape: self, style: ForegroundStyle())
    }
}

extension Shape {
    /// Fill this shape with a style — the foreground style in effect unless
    /// told otherwise.
    public func fill<S: ShapeStyle>(_ content: S = .foreground) -> some View {
        _ShapeView(shape: self, style: content)
    }

    /// Stroke this shape's outline with a style.
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: Double = 1) -> some View {
        _ShapeView(shape: self, style: content, strokeStyle: StrokeStyle(lineWidth: lineWidth))
    }

    /// Stroke this shape's outline with a style, the line as `style` draws it.
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle) -> some View {
        _ShapeView(shape: self, style: content, strokeStyle: style)
    }
}

/// A shape painted with a style of its own type: filled, or stroked when it
/// has a stroke style. Every `Shape` becomes one of these — used bare,
/// through its `body`, filled with the foreground style.
@View
public struct _ShapeView<S: Shape, Style: ShapeStyle> {
    let shape: S
    let style: Style
    /// How the outline is drawn; `nil` fills the shape.
    var strokeStyle: StrokeStyle? = nil

    public var body: Never { bodyUnavailable() }
}

extension _ShapeView: BuiltinView {
    /// The style is resolved here, against the environment the shape is
    /// built in: what it read — the color scheme, the foreground style — is
    /// read like any other value, and a change to it builds the shape again.
    func makeNode(_ context: inout BuildContext) -> ViewNode {
        let paint = style.paint(in: context.environment)
        let fill = strokeStyle == nil ? paint : nil
        let stroke = strokeStyle == nil ? nil : paint
        return ContentNode(content: ShapeContent(
            shape: shape,
            drawn: context.drawnShape(shape),
            fill: fill,
            stroke: stroke,
            strokeStyle: strokeStyle ?? StrokeStyle(),
            idealSize: nil,
            animatedFill: context.animatedPaint(.fill, fill),
            animatedStroke: context.animatedPaint(.stroke, stroke)
        ))
    }
}

/// The built-in shapes, which are nodes themselves rather than a body.
extension Shape {
    func makeShapeNode(_ context: inout BuildContext) -> ViewNode {
        _ShapeView(shape: self, style: ForegroundStyle()).makeNode(&context)
    }
}
