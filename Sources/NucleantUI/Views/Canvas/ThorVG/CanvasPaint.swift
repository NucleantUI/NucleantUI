//
//  CanvasPaint.swift
//  NucleantUI
//
//  `Path` for ThorVG: a shape class that takes the same path instructions a
//  `Canvas` does, and the calls a `ThorShape` is missing to follow them —
//  quadratic curves and arcs, which ThorVG has no native call for.
//
import NucleantThorVG

/// A ThorVG shape an author builds from `Path`s and keeps across frames.
///
/// ```swift
/// let ring = CanvasPaint(Path(ellipseIn: Rect(x: 10, y: 10, width: 80, height: 80)))
/// ring.set_stroke_width(4)
/// ring.set_stroke_color(r: 255, g: 255, b: 255)
/// context.add(shape: ring)
/// ```
///
/// Owns its paint the way `TCShape` does — a reference taken on creation and
/// given back on deinit — so the canvas dropping it does not free it under
/// the author. Move, resize and recolor it in place (`translate`, `scale`,
/// `set_fill_color`); `reset()` and `append` again only when the path itself
/// changes.
public final class CanvasPaint: ThorShape {
    public var base: Tvg_Paint

    public init(base: Tvg_Paint = tvg_shape_new()) {
        self.base = base
        _ = tvg_paint_ref(base)
    }

    /// A shape already holding `path`.
    public convenience init(_ path: Path) {
        self.init()
        append(path)
    }

    deinit {
        _ = tvg_paint_unref(base, true)
    }
}

extension ThorShape {

    /// Where the pen is: the last point of the path so far, or `nil` for an
    /// empty shape.
    var currentPoint: Point? {
        guard let last = get_path().pts.last else { return nil }
        return Point(x: Double(last.x), y: Double(last.y))
    }

    /// `path`'s instructions appended, each mapped through `transform`.
    /// Quadratic curves become the cubics through the same curve.
    public func append(_ path: Path, transform: Transform = .identity) {
        var current = Point.zero
        var subpathStart = Point.zero
        for element in path.applying(transform).elements {
            switch element {
            case .move(let point):
                _ = move_to(x: point.x, y: point.y)
                current = point
                subpathStart = point
            case .line(let point):
                _ = line_to(x: point.x, y: point.y)
                current = point
            case .quad(let control, let end):
                quad(from: current, control: control, to: end)
                current = end
            case .cubic(let c1, let c2, let end):
                _ = cubic_to(cx1: c1.x, cy1: c1.y, cx2: c2.x, cy2: c2.y, x: end.x, y: end.y)
                current = end
            case .close:
                _ = close()
                current = subpathStart
            case .rect(let rect, let radiusX, let radiusY):
                _ = append_rect(x: rect.minX, y: rect.minY, w: rect.width, h: rect.height, rx: radiusX, ry: radiusY)
            case .ellipse(let center, let radiusX, let radiusY):
                _ = append_circle(cx: center.x, cy: center.y, rx: radiusX, ry: radiusY)
            case .text, .image:
                // Not geometry: a ThorVG shape holds none.
                break
            }
        }
    }

    /// A quadratic curve from the current point.
    public func quad_to(control: Point, to end: Point) {
        quad(from: currentPoint ?? control, control: control, to: end)
    }

    /// An arc of the circle about `center` — see `Path.addArc`; `clockwise:
    /// true` runs through decreasing angles. A line joins the current point
    /// to its start.
    public func append_arc(center: Point, radius: Double, startAngle: Angle, endAngle: Angle, clockwise: Bool) {
        var arc = Path()
        if let current = currentPoint { arc.move(to: current) }
        arc.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
        appendContinuing(arc)
    }

    /// An arc of the circle about `center` through `delta` — see
    /// `Path.addRelativeArc`.
    public func append_relative_arc(center: Point, radius: Double, startAngle: Angle, delta: Angle) {
        var arc = Path()
        if let current = currentPoint { arc.move(to: current) }
        arc.addRelativeArc(center: center, radius: radius, startAngle: startAngle, delta: delta)
        appendContinuing(arc)
    }

    /// The rounded corner at `tangent1End` — see `Path.addArc(tangent1End:…)`.
    public func append_arc(tangent1End: Point, tangent2End: Point, radius: Double) {
        var arc = Path()
        if let current = currentPoint { arc.move(to: current) }
        arc.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius)
        appendContinuing(arc)
    }

    private func quad(from: Point, control: Point, to end: Point) {
        let c1 = Point(x: from.x + 2.0 / 3.0 * (control.x - from.x), y: from.y + 2.0 / 3.0 * (control.y - from.y))
        let c2 = Point(x: end.x + 2.0 / 3.0 * (control.x - end.x), y: end.y + 2.0 / 3.0 * (control.y - end.y))
        _ = cubic_to(cx1: c1.x, cy1: c1.y, cx2: c2.x, cy2: c2.y, x: end.x, y: end.y)
    }

    /// `arc` was built starting at the shape's current point, so its own
    /// leading move is already where the pen is: skip it.
    private func appendContinuing(_ arc: Path) {
        var rest = arc
        if case .move = rest.elements.first, currentPoint != nil { rest.elements.removeFirst() }
        append(rest)
    }
}
