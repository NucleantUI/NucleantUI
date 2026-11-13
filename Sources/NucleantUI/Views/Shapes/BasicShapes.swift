//
//  BasicShapes.swift
//  NucleantUI
//

/// A rectangle filling its frame.
@View
public struct Rectangle: Shape {
    public init(_viewID: ViewID = #viewID) { self._viewID = _viewID }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRect(rect)
        return path
    }
}

extension Rectangle: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

public enum RoundedCornerStyle: Hashable, Sendable {
    case circular
    case continuous
}

/// A rectangle with rounded corners.
@View
public struct RoundedRectangle: Shape {
    public var cornerRadius: Double
    public var style: RoundedCornerStyle

    public init(cornerRadius: Double, style: RoundedCornerStyle = .circular, _viewID: ViewID = #viewID) {
        self.cornerRadius = cornerRadius
        self.style = style
        self._viewID = _viewID
    }

    public var animatableData: Double {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        // Clamp: ThorVG draws a radius larger than half the shorter side as an
        // overlapping arc rather than a capsule.
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        path.addRect(rect, cornerRadius: radius)
        return path
    }
}

extension RoundedRectangle: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

/// A circle inscribed in its frame — SwiftUI's `Circle` uses the *smaller*
/// dimension and centres, which is what keeps it round in a non-square box.
@View
public struct Circle: Shape {
    public init(_viewID: ViewID = #viewID) { self._viewID = _viewID }

    public func path(in rect: Rect) -> Path {
        let diameter = min(rect.width, rect.height)
        let square = Rect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        var path = Path()
        path.addEllipse(in: square)
        return path
    }
}

extension Circle: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

/// An ellipse filling its frame.
@View
public struct Ellipse: Shape {
    public init(_viewID: ViewID = #viewID) { self._viewID = _viewID }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}

extension Ellipse: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

/// A rounded rectangle whose corner radius is half its shorter side.
@View
public struct Capsule: Shape {
    public var style: RoundedCornerStyle

    public init(style: RoundedCornerStyle = .circular, _viewID: ViewID = #viewID) {
        self.style = style
        self._viewID = _viewID
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRect(rect, cornerRadius: min(rect.width, rect.height) / 2)
        return path
    }
}

extension Capsule: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

/// The chevron a `NavigationStack` draws as its back button, Material's
/// `arrow_back_ios_new`, as a shape: fill or stroke it in any style for a
/// back button of your own.
///
/// It keeps the icon's proportions. The icon's 24-point box is scaled to
/// the frame's shorter side and centred, as a `Circle` is, so in a 20 × 20
/// frame it is the stack's chevron, point for point:
///
/// ```swift
/// .navigationBarBackButtonHidden()
/// .toolbar {
///     ToolbarItem(placement: .navigation) {
///         ArrowBack()
///             .fill(Color.orange)
///             .frame(width: 20, height: 20)
///             .frame(width: 36, height: 36)
///             .contentShape(Rectangle())
///             .onTapGesture { router?.pop() }
///     }
/// }
/// ```
@View
public struct ArrowBack: Shape {
    /// The icon's polygon, in its 24-point box.
    private static let points = [
        Point(x: 17.77, y: 3.77),
        Point(x: 16, y: 2),
        Point(x: 6, y: 12),
        Point(x: 16, y: 22),
        Point(x: 17.77, y: 20.23),
        Point(x: 9.54, y: 12),
    ]

    public init(_viewID: ViewID = #viewID) { self._viewID = _viewID }

    public func path(in rect: Rect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let left = rect.midX - side / 2
        let top = rect.midY - side / 2
        var path = Path()
        path.addLines(Self.points.map { Point(x: left + $0.x * scale, y: top + $0.y * scale) })
        path.closeSubpath()
        return path
    }
}

extension ArrowBack: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}

/// A caller-supplied path, built in the view's own coordinate space (origin at
/// the frame's top-left) and moved into place by the framework.
@View
public struct PathShape: Shape {
    let build: (Size) -> Path

    public init(_ build: @escaping (Size) -> Path, _viewID: ViewID = #viewID) {
        self.build = build
        self._viewID = _viewID
    }

    /// The closure is the whole shape, and two closures can't be compared:
    /// never equivalent, so a new one always draws.
    public func _isEquivalent(to other: PathShape) -> Bool { false }

    public func path(in rect: Rect) -> Path {
        build(rect.size).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

extension PathShape: BuiltinView {
    func makeNode(_ context: inout BuildContext) -> ViewNode { makeShapeNode(&context) }
}
